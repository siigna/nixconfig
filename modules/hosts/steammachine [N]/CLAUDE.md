# steammachine notes

Steam Machine (codename `fremont`) on the TV: boots straight into gaming mode as `deck`, and doubles
as a remote builder for nixdeck (listed in `nixbuild.nix` next to `nixbuilder`).

**No Jovian device module yet.** Upstream support is PR Jovian-Experiments/Jovian-NixOS#584
(`jovian.devices.steammachine`, plus `fremont-hw-support` firmware). Until it merges, the host sets
`jovian.hardware.has.amd.gpu` and `linuxPackages_latest` itself. Once it lands: replace both with
`jovian.devices.steammachine.enable = true;` (which defaults to the Jovian kernel).

**Session flow differs from nixdeck.** nixdeck logs `deck` in from GDM (`jovian-steamdeck`).
steammachine uses `jovian.steam.autoStart` — SDDM autologin with relogin, and
`desktopSession = "gamescope-wayland"`, so Switch to Desktop relaunches gaming mode. It does not
import `nixos-base` (GNOME/GDM/printing); `nixos-common` carries the shared bits.

**Builder.** `builder-service` accepts nixdeck's root key (`/root/.ssh/nixbuilder-key`) as both
`nix-ssh` and `root`. `nix.daemonCPUSchedPolicy`/`IOSchedClass` are `idle` so builds yield to games.

## Install

Partitions are referenced by label (`hardware.nix`), so no generated hardware config is needed:

```bash
# from a NixOS unstable installer USB, as root
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 1GiB set 1 esp on
parted /dev/nvme0n1 -- mkpart root ext4 1GiB 100%
mkfs.fat -F 32 -n BOOT /dev/nvme0n1p1
mkfs.ext4 -L nixos /dev/nvme0n1p2
mount /dev/disk/by-label/nixos /mnt
mount -o umask=077 --mkdir /dev/disk/by-label/BOOT /mnt/boot
nixos-generate-config --show-hardware-config --root /mnt   # compare initrd modules with hardware.nix
nix-shell -p git --run 'git clone https://github.com/siigna/nixconfig /mnt/etc/nixconfig'
nixos-install --flake /mnt/etc/nixconfig#steammachine
```

To skip compiling on the installer, build on nixdeck (`make build HOST=steammachine`), then
`nix copy --to 'ssh://root@<installer-ip>?remote-store=local?root=/mnt' ./result` and run
`nixos-install --system <that store path>` on the installer.

After first boot: `sudo tailscale up` (hostname must be `steammachine` for MagicDNS), `passwd
siigna`. Then deploy from nixdeck with `make switch HOST=steammachine TARGET=root@steammachine`.
