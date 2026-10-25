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
make build BUILDHOST=   # realise locally instead of on steammachine (e.g. it's off)
make update-claude      # update only the claude-code-nix flake input

make build HOST=steammachine                            # build another host
make switch HOST=steammachine TARGET=root@steammachine  # deploy over SSH
```

`build`/`switch`/`boot` target `.#$(HOST)` (default `nixdeck`); `TARGET` adds `--target-host`.
`BUILDHOST` (default `nix-ssh@steammachine`) adds `--build-host`: evaluation stays local, but
substitution and every build (including `preferLocalBuild` ones) happen on the Steam Machine and only
the finished closure is copied back, so a big nixpkgs bump doesn't swamp the Deck.
Evaluation is pure — if a build ever demands `--impure`, something has grown an absolute path or
`builtins.getEnv`; fix that rather than adding the flag back.

To roll back without rebooting:
```bash
nixos-rebuild switch --rollback
```

The flake directory can be anywhere — nothing hardcodes its location. All paths are relative to where `make` is run.

## Architecture

This is a NixOS configuration for two hosts — `nixdeck` (Steam Deck) and `steammachine` (Steam Machine on the TV, also nixdeck's remote builder) — using the **Dendritic Pattern** with **flake-parts** + **import-tree**.

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

**`modules/hosts/steammachine [N]/`** (Steam Machine):
- `flake-parts.nix` — `mkNixos "x86_64-linux" "steammachine"`
- `configuration.nix` — imports `nixos-common`, `jovian-fremont` (autostart via SDDM, Plasma desktop mode), `builder-service`, `tailscale`, `siigna`, `hosts-file`, `tv-apps`, `atop`, `lightbar`
- `hardware.nix` — registers `flake.modules.nixos.hardware-steammachine` (label-based root/ESP, zram)

Each host sets its own `networking.hostName` and `system.stateVersion`.

### Module naming convention

Directory suffix hints at platform scope (documentation only — not enforced by import-tree):
- `[N]` = NixOS only
- `[]` = generic/all platforms

### Key modules

| Module name | File |
|---|---|
| `nixos-common` | `system/common [N]/common.nix` — overlays, bootloader, Plymouth, NetworkManager, nix settings (nixdeck + steammachine) |
| `nixos-base` | `system/base [N]/base.nix` — imports `nixos-common`; GNOME, GDM monitors, printing, firewall, home-manager (nixdeck) |
| `system-packages` | `programs/packages [N]/system-packages.nix` — all system packages, Steam, Docker, VSCode |
| `jovian` | `services/jovian [N]/jovian.nix` — Jovian modules (master), Steam, Decky, `deck` user (nixdeck) |
| `jovian-fremont` | `services/jovian [N]/jovian.nix` — same module over input `jovian-nixos-fremont` (Jovian PR #598 test-merge) (steammachine) |
| `jovian-steamdeck` | `services/jovian [N]/jovian-steamdeck.nix` — Deck hardware + GDM session flow + `steamos-session-select` stub (nixdeck) |
| `tv-apps` | `programs/tv-apps [N]/tv-apps.nix` — Plex HTPC + Chrome kiosk launchers for YouTube TV, Netflix, Prime Video (steammachine) |
| `atop` | `programs/atop [N]/atop.nix` — atop datalogging (60 s) + process accounting; hourly `atopsar` text reports served on :8088, tailnet-only (steammachine) |
| `lightbar` | `programs/lightbar [N]/lightbar.nix` — light bar daemon: CPU/network meter (default), Nix-build breathing, fixed look or off; `sudo lightbar mode …` to switch live (steammachine) |
| `tailscale` | `services/tailscale [N]/tailscale.nix` — service + firewall rules (auth via `tailscale login`) |
| `nixbuild` | `services/nixbuild [N]/nixbuild.nix` — distributed builds: steammachine, then eu.nixbuild.net |
| `siigna` | `users/siigna [N]/siigna.nix` — primary user, wheel + dev groups |
| `breezy` | `programs/breezy [N]/breezy.nix` — Breezy Desktop XR driver + Decky plugin shim |
| `xreal-one` | `programs/xreal-one [N]/xreal-one.nix` — XReal One AR glasses: xreal-one-ctl + ar-compositor, udev rules, plugdev group |
| `obdium` | `programs/obdium [N]/obdium.nix` — OBD2 diagnostics app; adds siigna to `dialout` for ELM327 USB-serial adapters |
| `steam-library` | `services/steam-library [N]/steam-library.nix` — shared Steam library at `/var/lib/steam-library` (siigna + deck users) |
| `builder-service` | `services/builder-service [N]/builder-service.nix` — nix-ssh user + SSH daemon + `builder.authorizedKeys` for accepting remote builds (steammachine) |
| `intellij` | `programs/intellij [N]/intellij.nix` — IntelliJ IDEA |
| `radio` | `programs/radio [N]/radio.nix` — SDR / radio tools |
| `vesc-tool` | `programs/vesc-tool [N]/vesc-tool.nix` — VESC motor-controller IDE; adds siigna to `dialout` for `/dev/ttyACM*` |
| `fonts` | `programs/fonts [N]/fonts.nix` — comic-relief, font-awesome |
| `hosts-file` | `services/hosts-file [N]/hosts-file.nix` — static `networking.extraHosts` for LAN boxes (proxmox, nixmox, octopi) |
| `gdm-nopasswdlogin` | `services/gdm-nopasswdlogin [N]/gdm-nopasswdlogin.nix` — `nopasswdlogin` group + GDM PAM rule |
| `bootnext` | `services/bootnext [N]/bootnext.nix` — oneshot setting UEFI BootNext back to the current entry (SteamOS) |
| `nix-build-scratch` | `system/nix-build-scratch [N]/nix-build-scratch.nix` — build sandbox scratch on an ext4 image inside the NTFS volume |
| `boucheblaster` | `users/boucheblaster [N]/boucheblaster.nix` — secondary user (dialout, networkmanager, plugdev, uucp) |
| `claude-code` | `programs/claude-code [N]/claude-code.nix` — Claude Code + `/etc/claude-code/managed-settings.json` (statusline, hooks, pinned plugins) |
| `nix-index` | `programs/nix-index [N]/nix-index.nix` — prebuilt nix-index database (nix-index-database input), `nix-locate`, `comma`, command-not-found hook (nixdeck) |

### Per-module notes

Gotchas and design notes live in a `CLAUDE.md` next to the module they describe, loaded on demand
when a file in that directory is read. Read the one for the module before changing it:

- `services/jovian [N]/` — `jovian` vs `jovian-steamdeck` split, `jovian-fremont`, nixdeck's `steamos-session-select` stub, launch watchdog (`Type=simple`), `decky` user
- `programs/breezy [N]/` — xrlinuxdriver patches, Decky XRGaming shim, vkBasalt, IPC cleanup, session lifecycle (deeper detail in `xr_driver_notes.md`)
- `programs/xreal-one [N]/`, `programs/obdium [N]/`, `services/steam-library [N]/`
- `services/gdm-nopasswdlogin [N]/` — PAM rule must use `.rules`, not `.text`, or every GDM login fails
- `system/nix-build-scratch [N]/` — why `/var/nix-build` is an ext4 image on the NTFS volume
- `hosts/steammachine [N]/` — Jovian device module from unmerged PR #598 (`jovian-fremont`), SDDM/Plasma session switching, HDMI-CEC, deploy, PXE reinstall recipe
- `programs/claude-code [N]/` — managed settings, plugin marketplace, Dippy wrapper
- `packages/fargo-dtc4250e-driver/` — the `requireFile` src and how to satisfy it

### Custom packages

`packages/` is a nixpkgs overlay (flake input `packages`, `flake = false`). `nixos-common` sets
`nixpkgs.overlays` to five overlays, in order: `(import inputs.packages)`, `claude-code-nix`,
`codex-cli-nix`, `hermes-agent`, `vesc-tool`. The last four come from flake inputs that track upstream
faster than nixpkgs does (`hermes-agent` isn't in nixpkgs at all; its overlay aliases the flake's own
uv2nix build, with `nixpkgs` followed).

| Package | Path | Notes |
|---|---|---|
| `adi1090x-plymouth` | `packages/adi1090x-plymouth/` | Custom Plymouth theme |
| `alsa-ucm-conf` | `packages/alsa-ucm-conf/` | ALSA UCM 1.2.8 downgrade — **commented out** in `packages/default.nix` |
| `ar-compositor` | `packages/ar-compositor/` | AR passthrough compositor for XReal One Pro (Python/GTK3/GStreamer) |
| `breezy-gnome` | `packages/breezy/breezy-gnome.nix` | Breezy GNOME extension |
| `xrlinuxdriver` | `packages/breezy/xrlinuxdriver.nix` | Patched Breezy XR driver binary |
| `llama` | `packages/llama/` | llama.cpp — **not in the overlay**; standalone `shell.nix` only |
| `obdium` | `packages/obdium/` | OBD2 diagnostics app; built against pinned nixpkgs-webkitgtk40 |
| `xreal-one-ctl` | `packages/xreal-one-ctl/` | CLI for XReal One AR glasses (Rust; from 0xcaff/xr-tools) |
| `fargo-dtc4250e-driver` | `packages/fargo-dtc4250e-driver/` | CUPS PPD + filter for the Fargo DTC4250e card printer (wired up in `base.nix`); `src` is a `requireFile` |
| `goccc` | `packages/goccc/` | Claude Code cost statusline; patched to price OpenRouter model IDs |
| `dippy` | `packages/dippy/` | Claude Code hook auto-approving read-only shell commands |
| `agnix` | `packages/agnix/` | Linter for CLAUDE.md, skills, hooks, plugin and MCP config |
| `claude-plugins` | `packages/claude-plugins/` | Local plugin marketplace built from pinned upstream repos |
| `empryo` | `packages/empryo/` | Empryo (ex-SoulForge) AI coding agent; prebuilt unfree Bun binary, `deps/` kept beside it in `libexec` |

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
3. Add `<name>` to the imports list in the host's `configuration.nix` (`modules/hosts/<host> [N]/`)
4. `git add` it — flakes ignore untracked files in a dirty git tree, so a new module file is
   invisible until staged and fails with `error: undefined variable '<name>'`
