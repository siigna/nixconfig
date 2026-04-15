# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common commands

```bash
make build    # build without activating (creates ./result symlink)
make switch   # build and activate immediately
make boot     # build and activate on next boot only
make update   # nix flake update (refresh flake.lock)

make build FLAKE=0      # same targets but using /etc/nixos (legacy fallback)
make build NOBUILDERS=1 # build without distributed builders (bypasses nixbuild.net)
make update-claude      # update only the claude-code-nix flake input
make image-nixbuilder   # build a qcow2 image for the nixbuilder Proxmox VM
```

To roll back without rebooting:
```bash
nixos-rebuild switch --rollback
```

The flake directory can be anywhere — nothing hardcodes its location. All paths are relative to where `make` is run.

## Architecture

This is a NixOS configuration for two hosts — `nixdeck` (Steam Deck) and `nixbuilder` (Proxmox VM used as a remote build machine) — using the **Dendritic Pattern** with **flake-parts** + **import-tree**.

### How it works

`flake.nix` delegates everything to `flake-parts`, which recursively imports all `.nix` files under `modules/` via `import-tree`. Every file in `modules/` is a **flake-parts module** — a function accepting `{ inputs, lib, ... }:`.

There are two kinds of files:

- **`flake-parts.nix`** — contributes to flake-level outputs (`flake.nixosConfigurations`, etc.)
- **Everything else** — contributes a NixOS module to `flake.modules.nixos.<name>`

The `flake.modules.nixos` option is enabled by `inputs.flake-parts.flakeModules.modules` (imported in `modules/nix/flake-parts []/lib.nix`). Registered modules become outputs at `outputs.modules.nixos.<name>`, accessible via `inputs.self.modules.nixos.<name>`.

### Host wiring

**`modules/hosts/nixdeck [N]/`** (Steam Deck):
- `flake-parts.nix` — calls `mkNixos "x86_64-linux" "nixdeck"` to create the nixosConfiguration
- `tracking-flake-parts.nix` — calls `mkNixosTracked "x86_64-linux" "nixdeck"` for the optional tracked build
- `configuration.nix` — registers `flake.modules.nixos.nixdeck` importing all other named modules
- `hardware.nix` — registers `flake.modules.nixos.hardware-nixdeck` (filesystems, kernel modules, AMD microcode)

**`modules/hosts/nixbuilder [N]/`** (Proxmox build VM):
- `flake-parts.nix` — calls `mkNixos "x86_64-linux" "nixbuilder"` (buildable as a qcow2 image via `make image-nixbuilder`)
- `configuration.nix` — imports `builder-service` + `tailscale`; sets `nixbuilder.authorizedKeys` and a local `admin` user for bootstrap access

### Module naming convention

Directory suffix hints at platform scope (documentation only — not enforced by import-tree):
- `[N]` = NixOS only
- `[]` = generic/all platforms

### Key modules

| Module name | File |
|---|---|
| `nixos-base` | `system/base [N]/base.nix` — boot, networking, GNOME, firewall, nix settings |
| `system-packages` | `programs/packages [N]/system-packages.nix` — all system packages, Steam, Docker, VSCode |
| `jovian` | `services/jovian [N]/jovian.nix` — Steam Deck hardware via `inputs.jovian-nixos` |
| `tailscale` | `services/tailscale [N]/tailscale.nix` — service + firewall rules (auth via `tailscale login`) |
| `nixbuild` | `services/nixbuild [N]/nixbuild.nix` — distributed builds via eu.nixbuild.net |
| `siigna` | `users/siigna [N]/siigna.nix` — primary user, wheel + dev groups |
| `breezy` | `programs/breezy [N]/breezy.nix` — Breezy Desktop XR driver + Decky plugin shim |
| `xreal-one` | `programs/xreal-one [N]/xreal-one.nix` — XReal One AR glasses: xreal-one-ctl + ar-compositor, udev rules, plugdev group |
| `obdium` | `programs/obdium [N]/obdium.nix` — OBD2 diagnostics app; adds siigna to `dialout` for ELM327 USB-serial adapters |
| `steam-library` | `services/steam-library [N]/steam-library.nix` — shared Steam library at `/var/lib/steam-library` (siigna + deck users) |
| `builder-service` | `services/builder-service [N]/builder-service.nix` — nix-ssh user + SSH daemon config for accepting remote builds |
| `intellij` | `programs/intellij [N]/intellij.nix` — IntelliJ IDEA |
| `radio` | `programs/radio [N]/radio.nix` — SDR / radio tools |

### jovian.nix notes

The `jovian-stubs` package is overridden via `nixpkgs.overlays` to replace `steamos-session-select` with a working implementation. The upstream stub calls `steamosctl switch-to-desktop-mode` which hangs because the `SessionManagement1` D-Bus interface is absent in Jovian's `steamos-manager`. The override kills `$gamescope_pid` directly (or stops `gamescope-session.target` as a fallback), which drops the `deck` user back to GDM.

The stub is injected at the front of PATH inside the Steam bubblewrap via the FHS profile (`steam-run-1.0.0.85-fhsenv-profile`), so system-level PATH overrides have no effect — the overlay is the only way to intercept it.

A `steam-launch-watchdog` user service starts with the gamescope session and terminates it after 90 seconds if `steam-launcher.service` never became active, returning the user to GDM.

`jovian.decky-loader.user` is set to `"deck"` (matching SteamOS). The Jovian default `"decky"` is a system user with nologin shell, which breaks the XRGaming plugin's `su -l` calls. The `su` wrapper in `extraPackages` delegates to `runuser` because the real `su` requires a TTY that the decky-loader systemd service lacks.

### breezy.nix notes

Breezy Desktop (XR glasses driver) is installed system-wide via Nix. The custom `xrlinuxdriver` package in `packages/breezy/` carries five source patches (see `xr_driver_notes.md` for full details):

1. **`ipc-mutex-robust.patch`** — treats EPERM from `pthread_mutex_destroy` as non-fatal (the GNOME extension holds an mmap on the shared memory mutex)
2. **`config-inotify-directory.patch`** — watches the config *directory* for `MOVED_TO` instead of the file for `DELETE_SELF`, so `os.replace()` config writes are detected
3. **`state-null-check.patch`** — prevents segfault in `write_state` when `fopen` returns NULL due to `fs.protected_regular=1`
4. **`reenable-device-reconnect.patch`** — calls `exit(0)` on runtime re-enable so systemd restarts the driver with a fresh device pipeline (the device thread has race conditions that prevent reconnection otherwise)
5. **`startup-license-race.patch`** — re-reads config after `plugins.start()` in `main()` to fix a startup race where `is_productivity_granted()` is cached as `false` before the license is fetched. Without this, `breezy_desktop.enabled` stays `false` on startup (even with valid trial/license), IMU file never updates, and the GNOME extension never activates.

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

### xreal-one.nix notes

`xreal-one-ctl` (from `packages/xreal-one-ctl/`) is a Rust CLI built from the [0xcaff/xr-tools](https://github.com/0xcaff/xr-tools) workspace. Primary use: `xreal_one_ctl enable-camera` turns on the XReal One Pro's passthrough eye camera, causing the device to reconnect and expose a UVC camera interface.

`ar-compositor` (from `packages/ar-compositor/`) is a Python/GTK3/GStreamer app that composites the glasses camera feed with a Mutter ScreenCast desktop capture, with a live preview window and a Record button. Saves recordings to `~/Videos`.

Both tools need USB access without sudo — the module adds udev rules for vendor ID `0x3318` (XReal) granting `plugdev` group access, and adds siigna to `plugdev`.

### obdium.nix notes

`obdium` (from `packages/obdium/`) is an OBD2 automotive diagnostics app. It requires `webkitgtk_4_0` (based on libsoup2 / Tauri v1 / wry <0.38), which was removed from nixpkgs-unstable around 2025-10-08. The package is built using `nixpkgs-webkitgtk40` (pinned to commit `10924657b0dc`), a flake input specifically added to preserve this dependency.

The module adds siigna to the `dialout` group for access to ELM327 USB-serial adapters on `/dev/ttyUSB*`.

### steam-library.nix notes

Creates a `steam-library` group and a shared directory at `/var/lib/steam-library` (mode 2775, owned by root:steam-library). Both `siigna` and `deck` users are added to the group, allowing cross-user Steam library sharing between desktop and gaming sessions.

### Custom packages

`packages/` is a nixpkgs overlay (flake input `packages`, `flake = false`). Applied in `nixos-base` via `nixpkgs.overlays = [ (import inputs.packages) ]`.

| Package | Path | Notes |
|---|---|---|
| `adi1090x-plymouth` | `packages/adi1090x-plymouth/` | Custom Plymouth theme |
| `alsa-ucm-conf` | `packages/alsa-ucm-conf/` | ALSA UCM config overrides |
| `ar-compositor` | `packages/ar-compositor/` | AR passthrough compositor for XReal One Pro (Python/GTK3/GStreamer) |
| `breezy-gnome` | `packages/breezy/breezy-gnome.nix` | Breezy GNOME extension |
| `xrlinuxdriver` | `packages/breezy/xrlinuxdriver.nix` | Patched Breezy XR driver binary |
| `llama` | `packages/llama/` | llama.cpp (local LLM inference) |
| `obdium` | `packages/obdium/` | OBD2 diagnostics app; built against pinned nixpkgs-webkitgtk40 |
| `xreal-one-ctl` | `packages/xreal-one-ctl/` | CLI for XReal One AR glasses (Rust; from 0xcaff/xr-tools) |

**Dual-nixpkgs strategy**: packages requiring `webkitgtk_4_0` (obdium, and breezy-gnome's build dependencies) accept a `pkgs-webkitgtk40` argument wired to the pinned nixpkgs. The overlay's `default.nix` passes it through so these packages build without polluting the main nixpkgs set.

### Option dependency tracking

An optional `nixdeck-tracked` configuration uses [oddlama/nixos-config-tui](https://github.com/oddlama/nixos-config-tui) to track which NixOS options depend on which. Not for day-to-day use — useful for auditing changes or verifying a refactor didn't shift anything unintentionally.

Uses three flake inputs: `nix-tracking` (patched nix evaluator binary), `nixpkgs-tracking` (oddlama's fork, only used for the `nixos-config` TUI binary), and `nixos-config-tui` (patch files). The tracked system build itself patches our own nixpkgs via `nixos-config-tui` so it shares package store paths with the regular build — no double compilation of packages.

```bash
make track-build          # build nixdeck-tracked (result → ./result)
make track-show           # browse option tree from flake ref (no prior build needed)
make track-show-result    # browse ./result from a prior track-build
make track-diff           # diff all options: /run/current-system vs ./result
make track-diff-explicit  # diff only explicitly defined values (less noise)
make track-text-diff      # pseudo-nix diff of explicitly defined values
```

### Adding a new module

1. Create `modules/<category>/<name> [N]/<name>.nix`
2. Return `{ flake.modules.nixos.<name> = { pkgs, lib, ... }: { ... }; }`
3. Add `<name>` to the imports list in `modules/hosts/nixdeck [N]/configuration.nix`
