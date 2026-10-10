# breezy.nix notes

Breezy Desktop (XR glasses driver) is installed system-wide via Nix. The custom `xrlinuxdriver` package in `packages/breezy/` carries five source patches (see `xr_driver_notes.md` for full details):

1. **`ipc-mutex-robust.patch`** — treats EPERM from `pthread_mutex_destroy` as non-fatal (the GNOME extension holds an mmap on the shared memory mutex)
2. **`config-inotify-directory.patch`** — watches the config *directory* for `MOVED_TO` instead of the file for `DELETE_SELF`, so `os.replace()` config writes are detected
3. **`state-null-check.patch`** — prevents segfault in `write_state` when `fopen` returns NULL due to `fs.protected_regular=1`
4. **`reenable-device-reconnect.patch`** — calls `exit(0)` on runtime re-enable so systemd restarts the driver with a fresh device pipeline (the device thread has race conditions that prevent reconnection otherwise)
5. **`startup-license-race.patch`** — re-reads config after `plugins.start()` in `main()` to fix a startup race where `is_productivity_granted()` is cached as `false` before the license is fetched. Without this, `breezy_desktop.enabled` stays `false` on startup (even with valid trial/license), IMU file never updates, and the GNOME extension never activates.

`breezy-gnome.nix` applies one patch of its own, `window-scrollable.patch`, via an explicit
`patch -p1` (not `patches`) because the source tree contains symlinks that `patch`/`substituteInPlace`
would follow.

**Decky XRGaming plugin shim** (`breezyDeckyShim` activation script):
- Patches `main.py`: replaces `is_driver_running()` (which needs deck's D-Bus session, absent at boot) with a unit-file existence check; fixes hardcoded UID 1000 → deck's actual UID (1001).
- Patches `PyXRLinuxDriverIPC/xrdriveripc.py`: fixes the same UID 1000 hardcoding for `reset_driver()`.
- Pre-populates plugin settings (`installed_from_plugin_version`, `manifest_checksum`) and creates a `breezy_vulkan_verify` shim.
- Extracts vkBasalt libraries, reshade shaders, and vkBasalt config from the plugin's bundled tarball into deck's home directory.
- Always patches from `.orig` backups so re-running activation is idempotent. If the plugin is updated through Decky, delete the `.orig` files so fresh backups are taken.

**vkBasalt Vulkan layer** (for gamescope/Steam gaming mode):
- Layer JSON installed system-wide in `/etc/vulkan/implicit_layer.d/` because Steam recreates `~/.local/share/vulkan/implicit_layer.d/` at login.
- Libraries are FHS binaries in `~deck/.local/lib{,32}/` — only work inside Steam's FHS sandbox.
- `ENABLE_VKBASALT=1` set in `jovian.steam.environment` (Jovian doesn't set the `SteamDeck` env var that SteamOS uses).

**Cross-user IPC cleanup** (`xr-driver-cleanup@` system template service):
- The xrDriver binary uses System V shared memory (`shmget`/`ftok` on `/tmp/shader_runtime_*`) and regular files in `/dev/shm/`. Under `fs.protected_regular=1`, files in sticky-bit directories (`/tmp`, `/dev/shm`) can't be opened with `O_CREAT` by a different user.
- A root-level systemd template service cleans stale SysV segments (perms 666, nattch 0) and IPC files before each xr-driver start.
- Invoked via `ExecStartPre` using a scoped NOPASSWD sudo rule.

**Session lifecycle management** (`xr-driver` + `xr-driver-seat-watcher`):
- `xr-driver` is bound to `graphical-session.target` (active for both GNOME and gamescope/deck) via `WantedBy` + `PartOf`, so it stops automatically on logout.
- `xr-driver-seat-watcher` is a companion user service that monitors the logind session's `Active` D-Bus property. When the user switches away (`Active→false`), it stops xr-driver, releasing the USB device. When the user switches back (`Active→true`), it starts xr-driver fresh (triggering cleanup + device grab). No manual intervention needed for user switching in either direction.

**`breezyGnomeSetup` activation script**: Creates `~/.local/bin/xr_driver_cli` as a symlink to `/run/current-system/sw/bin/xr_driver_cli` for the siigna user. The GNOME extension's keyboard toggle shortcut (`_toggle_xr_effect`) looks for the CLI at `$XDG_BIN_HOME/xr_driver_cli` then `/usr/bin/xr_driver_cli`; neither exists on NixOS without the symlink.

**Extension debugging**: Logs go to `~/.local/state/breezy_gnome/logs/gjs/YYYY-MM-DD.log` (NOT the journal). Enable debug with `gsettings set com.xronlinux.BreezyDesktop debug true`. Key diagnostic: "Ready, enabling XR effect" means the effect activated; "device stream not being received" means `breezy_desktop_running` stayed false.

**Root cause of GNOME side not working** (fixed by `startup-license-race.patch`): At startup, `main()` calls `update_config_from_file()` before `plugins.start()`. The `device_license` plugin makes a blocking network request, so when config is first parsed, `is_productivity_granted()` caches `false` → `bd_config->enabled = false` → IMU file never written with `enabled=true` → extension keepalive expires → `breezy_desktop_running` stays false → no XR effect. The fix re-reads config after `plugins.start()` so the feature check uses the fetched license.
