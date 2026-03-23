# XR Driver NixOS Integration Notes

Detailed notes from the 2026-03-22 session getting Breezy Desktop (XR glasses driver) working on NixOS with both the GNOME desktop and Steam/gamescope (Decky XRGaming plugin).

## System overview

- **Host**: nixdeck (Steam Deck, x86_64-linux)
- **Users**: siigna (uid 1000, GNOME desktop), deck (uid 1001, gamescope/Steam)
- **Driver**: xrlinuxdriver v2.9.11 (C, built with cmake + cargo/Rust)
- **Desktop app**: Breezy Desktop (Python GTK4, GNOME Shell extension)
- **Steam plugin**: Decky XRGaming (Python, vkBasalt Vulkan layer)
- **Glasses**: XREAL One Pro (vendor 0x3318, product 0x0436)

## Architecture: how Breezy Desktop works

### Driver (`xrDriver`)
- Systemd user service (`xr-driver.service`), runs per-user
- Connects to XR glasses via USB/libusb, reads IMU data
- Writes head tracking data to:
  - `/dev/shm/breezy_desktop_imu` — mmap'd binary shared memory (GNOME extension reads this)
  - `/tmp/shader_runtime_*` — System V shared memory via `ftok()`/`shmget()` (vkBasalt reads this)
  - `/dev/shm/xr_driver_state` — text state file (apps read this)
- Reads control flags from `/dev/shm/xr_driver_control` (apps write this)
- Reads config from `~/.config/xr_driver/config.ini` via inotify

### Desktop rendering (GNOME)
- GNOME Shell extension `breezydesktop@xronlinux.com` reads `/dev/shm/breezy_desktop_imu` via mmap
- The extension applies a compositor shader effect to move the screen with head tracking
- The Breezy Desktop GTK app manages config and communicates with the driver

### Gamescope rendering (Steam)
- vkBasalt Vulkan implicit layer injects the Sombrero reshade shader
- The shader reads `/tmp/shader_runtime_*` (System V shared memory) for head tracking data
- Enabled via `ENABLE_VKBASALT=1` environment variable in gamescope session

### Decky XRGaming plugin
- Runs inside decky-loader (root systemd service)
- Manages xr-driver for the deck user via `su -l deck`
- Checks if breezy is installed, shows UI for XR settings in Steam

## Problems solved

### 1. Decky plugin can't find `su` (and other tools)
**Problem**: decky-loader's PATH only includes coreutils, findutils, grep, sed, systemd. Missing `su`, `bash`, etc.
**Fix**: `jovian.decky-loader.extraPackages` adds `su` wrapper and `bash`.

### 2. `su` requires a TTY
**Problem**: `/run/wrappers/bin/su` requires a TTY. The decky-loader systemd service has none.
**Fix**: `su` wrapper delegates to `runuser` (`util-linux`) which works from root without a TTY.

### 3. `DECKY_USER` is `decky` (nologin system user), not `deck`
**Problem**: Jovian default creates a `decky` system user with nologin shell. The plugin runs `su -l decky` which fails with "This account is currently not available."
**Fix**: `jovian.decky-loader.user = "deck"` to match SteamOS.

### 4. `LD_LIBRARY_PATH` KeyError
**Problem**: The XRGaming plugin does `del env_copy["LD_LIBRARY_PATH"]` assuming Steam set it. The Decky service doesn't have it.
**Fix**: `systemd.services.decky-loader.environment.LD_LIBRARY_PATH = ""`.

### 5. Plugin's FHS install script can't run on NixOS
**Problem**: The plugin downloads a tarball with FHS binaries that need `/usr/lib`, `/usr/bin`, etc. NixOS doesn't have these paths.
**Fix**: Install breezy-desktop via Nix, then shim the plugin's verification checks (settings, manifest checksum, verify script) via an activation script so the plugin thinks it's already installed.

### 6. Hardcoded UID 1000 in plugin
**Problem**: The plugin hardcodes `XDG_RUNTIME_DIR=/run/user/1000`. On NixOS, deck is uid 1001.
**Fix**: Activation script patches `main.py` and `xrdriveripc.py` via sed, using `.orig` backups for idempotency.

### 7. `is_driver_running()` needs deck's D-Bus session (absent at boot)
**Problem**: The plugin calls `su -l deck -c 'systemctl --user is-active xr-driver'` at boot. Deck hasn't logged in yet, so the user bus doesn't exist.
**Fix**: Activation script patches `is_driver_running()` to check for the unit file on disk instead (`glob.glob('/etc/systemd/user/xr-driver.service')`).

### 8. `fs.protected_regular=1` blocks cross-user file access
**Problem**: xrDriver opens `/tmp/shader_runtime_*` and `/dev/shm/xr_*` with `O_CREAT`. Linux's `fs.protected_regular=1` prevents this if another user owns the file in a sticky-bit directory. Switching between deck and siigna sessions causes crashes.
**Fix**: System-level template service `xr-driver-cleanup@` runs as root before each xr-driver start (invoked via NOPASSWD sudo). Cleans stale System V shared memory segments (perms 666, nattch 0) and IPC files. Also cleans at boot via `systemd.tmpfiles.rules`.

### 9. `write_state` segfault (NULL FILE pointer)
**Problem**: `write_state()` calls `fopen()` then `fprintf()` without checking for NULL. When `fopen` fails (cross-user file in `/dev/shm`), `fprintf(NULL, ...)` segfaults.
**Fix**: `state-null-check.patch` — adds NULL check on `fp`, returns early if fopen failed.

### 10. `pthread_mutex_destroy` EPERM crash
**Problem**: xrDriver creates a `PTHREAD_PROCESS_SHARED` mutex in `/dev/shm/breezy_desktop_imu` (mmap'd shared memory). The GNOME extension also mmaps this file. On driver restart, `pthread_mutex_destroy` returns EPERM because another process (the extension) still has the mapping. The driver treats EPERM as fatal and exits.
**Fix**: `ipc-mutex-robust.patch` — treats EPERM and EOWNERDEAD as non-fatal (like EINVAL already was), since the mutex is about to be reinitialized anyway.

### 11. Config inotify doesn't detect `os.replace()`
**Problem**: The driver watches `config.ini` by inode via `inotify(IN_CLOSE_WRITE | IN_DELETE_SELF)`. The Breezy Desktop app and `xr_driver_cli` use `os.replace()` (atomic rename) which creates a new inode. The driver's watch stays on the old (deleted) inode and never fires. The driver tries to re-add on `IN_DELETE_SELF` but `os.replace` generates `MOVED_TO` on the directory, not `DELETE_SELF` on the file.
**Fix**: `config-inotify-directory.patch` — watches the config *directory* for `IN_CLOSE_WRITE | IN_MOVED_TO` and filters events by filename. Works for both `sed -i` (CLOSE_WRITE) and `os.replace` (MOVED_TO).

### 12. Driver doesn't reconnect device on re-enable
**Problem**: When the driver is disabled via config, it logically disconnects the device (`connection_pool_disconnect_all`). When re-enabled, `evaluate_block_on_device_ready()` checks `device_present()` which returns false (device was cleared). The device thread stays blocked. The USB monitor only fires on physical hotplug events, not logical reconnects.
**Fix**: `reenable-device-reconnect.patch` — when `driver_reenabled` and not the first config read (startup), calls `exit(0)`. systemd's `Restart=always` brings the driver back with a fresh device pipeline. A `first_config_read` static flag prevents infinite restart loops (fresh start with enabled config would otherwise always look like a re-enable).

### 13. vkBasalt layer files wiped by Steam
**Problem**: Steam recreates `~/.local/share/vulkan/implicit_layer.d/` at login, wiping any user-placed vkBasalt layer JSON files.
**Fix**: Layer JSON installed system-wide in `/etc/vulkan/implicit_layer.d/` via `environment.etc`. Libraries and config stay in deck's home (set up by activation script from the plugin's bundled tarball).

### 14. `ENABLE_VKBASALT` not set in gamescope
**Problem**: On SteamOS, the vkBasalt layer uses `SteamDeck` as the enable environment variable. Jovian NixOS doesn't set `SteamDeck=1`.
**Fix**: `jovian.steam.environment.ENABLE_VKBASALT = "1"` and layer JSON uses `ENABLE_VKBASALT` instead of `SteamDeck`.

### 15. Startup race: `is_productivity_granted()` cached before license is fetched
**Problem**: In `main()`, `update_config_from_file()` is called at line 677 BEFORE `plugins.start()` at line 688. `device_license_start_func()` (called by `plugins.start()`) makes a *synchronous* blocking curl request to fetch the license and populate `state()->granted_features`. When the config is parsed first, `is_productivity_granted()` finds `granted_features = NULL`, returns `false`, and **caches** that result. After `plugins.start()` the cache is reset (via `reset_productivity_features()`), but the config is never re-parsed. So `bd_config->enabled` stays `false` even with a valid trial/paid license, and `breezy_desktop_write_pose_data()` is never called — the IMU file stays stale. The extension's keepalive check expires, `breezy_desktop_running` stays `false`, and the XR effect never activates.
**Fix**: `startup-license-race.patch` — adds `rewind(config_fp); update_config_from_file(config_fp);` immediately after `plugins.start()` in `main()`. This re-parses the config with the now-populated `granted_features`, so `bd_config->enabled = true` before the device thread starts. The second parse is otherwise identical: `driver_reenabled = false` (config hasn't changed), `first_config_read = false` (already set), so neither the exit nor a loop triggers.
**Why it worked sometimes**: When the user explicitly toggled breezy in the GTK app, the app wrote to `config.ini`, inotify fired, and `update_config_from_file` was called *after* `plugins.start()` had completed — at which point `is_productivity_granted()` returned `true`. This is why manually enabling in the GTK app occasionally fixed it, but the fix was unreliable due to timing.

### 16. Extension keyboard toggle can't find `xr_driver_cli`
**Problem**: The GNOME extension's `_toggle_xr_effect()` uses `xr_driver_cli`. It checks `$XDG_BIN_HOME/xr_driver_cli` (defaulting to `~/.local/bin/xr_driver_cli`) then `/usr/bin/xr_driver_cli`. Neither path exists on NixOS; the binary is in the nix store via `/run/current-system/sw/bin/xr_driver_cli`. Without the CLI, `this._cli_file = null` and the keyboard shortcut silently does nothing.
**Fix**: `breezyGnomeSetup` activation script creates `~/.local/bin/xr_driver_cli` as a symlink to `/run/current-system/sw/bin/xr_driver_cli` for the siigna user.

## Open issues

No known open issues as of 2026-03-22. Both GNOME desktop and gamescope/Steam sides are confirmed working.

### Transient: license server HTTP 500
The license server occasionally returns HTTP 500 during the startup `plugins.start()` curl request
(observed once at 21:52:23 on 2026-03-22). When this happens `tiers: {}` is logged in the driver
state and features are not granted. This is a transient server-side error; restarting the driver
(`systemctl --user restart xr-driver`) resolves it. Not a NixOS-specific issue.

## Resolved

### GNOME Shell extension not rendering — **FIXED by #15 + #16** (confirmed 2026-03-22)
`startup-license-race.patch` confirmed working. Extension log at 17:07:01 shows
`"Ready, enabling XR effect"` firing automatically on startup when glasses are connected
and breezy_desktop is enabled in config. Driver log at 17:06:59 shows
`"Breezy desktop has been enabled"` before device was found — the second
`update_config_from_file()` after `plugins.start()` correctly picked up the fetched license.

Extension keyboard toggle also fixed by `breezyGnomeSetup` activation script symlinking
`xr_driver_cli` to `~/.local/bin/`.

### Gamescope/Steam side — **working**
The vkBasalt layer loads successfully in gamescope (confirmed via journal: `vkBasalt info: effects = sombrero`). The XR effect works in Steam games after toggling the XRGaming Decky plugin settings. The Decky plugin UI shows glasses connected and allows reset driver.

## File inventory

### NixOS modules
- `modules/programs/breezy [N]/breezy.nix` — main breezy module (driver, udev, cleanup, Decky shim, vkBasalt layer)
- `modules/services/jovian [N]/jovian.nix` — Decky loader config, su/runuser wrapper, ENABLE_VKBASALT

### Driver patches (in `packages/breezy/`)
- `ipc-mutex-robust.patch` — EPERM non-fatal in pthread_mutex_destroy
- `config-inotify-directory.patch` — watch directory instead of file for config changes
- `state-null-check.patch` — NULL check in write_state
- `reenable-device-reconnect.patch` — exit(0) on runtime re-enable for clean restart
- `startup-license-race.patch` — re-read config after plugins.start() so breezy_desktop.enabled is correct

### Package definitions (in `packages/breezy/`)
- `default.nix` — top-level breezy-desktop package (symlinkJoin of xrlinuxdriver + breezy-gnome)
- `xrlinuxdriver.nix` — xrDriver binary + xr_driver_cli + systemd unit + udev rules
- `breezy-gnome.nix` — GNOME Shell extension + GTK app
