# steammachine notes

Steam Machine (codename `fremont`, Valve "Fremont" DMI) on the TV: boots straight into gaming mode
as `deck`, and is nixdeck's remote builder (`nixbuild.nix`, ahead of nixbuild.net).

Hardware as installed: AMD Custom CPU 1772 (12 threads), Navi 33 GPU, 16 GB RAM, 512 GB Kingston
NVMe (`nvme0n1`), Realtek RTL8111 ethernet (`enp5s0`), Qualcomm WCN6855 Wi-Fi (`wlp6s0`, ath11k).

**No Jovian device module yet.** Upstream support is PR Jovian-Experiments/Jovian-NixOS#584
(`jovian.devices.steammachine`, plus `fremont-hw-support` firmware). Until it merges, the host sets
`jovian.hardware.has.amd.gpu` and `linuxPackages_latest` itself. Once it lands: replace both with
`jovian.devices.steammachine.enable = true;` (which defaults to the Jovian kernel).

**Session flow differs from nixdeck.** nixdeck logs `deck` in from GDM (`jovian-steamdeck`).
steammachine uses `jovian.steam.autoStart` — SDDM autologin with relogin, and
`desktopSession = "gamescope-wayland"`, so Switch to Desktop relaunches gaming mode. It does not
import `nixos-base` (GNOME/GDM/printing); `nixos-common` carries the shared bits.
`jovian-setup-desktop-session` is disabled: it pushes `desktopSession` into steamos-manager, which
rejects `gamescope-wayland` ("Invalid desktop session") and leaves a failed user unit.

**Builder.** `builder-service` accepts nixdeck's root key (`/root/.ssh/nixbuilder-key`, named for
the retired Proxmox VM) as both `nix-ssh` and `root`, via `builder.authorizedKeys`.
`nix.daemonCPUSchedPolicy`/`IOSchedClass` are `idle` so builds yield to games.

**Networking.** Wi-Fi only in normal use. The NetworkManager profile (with PSK) was copied from
nixdeck at install time into `/etc/NetworkManager/system-connections/`; it is deliberately not in
the repo. `tailscale up` was run once by hand; the node is `steammachine` on the tailnet.

## Deploy

```bash
make switch HOST=steammachine TARGET=root@steammachine
```

Needs nixdeck switched to a config whose `nixbuild` module has the `Host steammachine` ssh entry,
otherwise root's ssh offers the wrong key ("Permission denied (publickey)").

## Reinstall (PXE over a direct cable)

The repo is private, so the installer never clones it: nixdeck builds the system and pushes it.
Done this way on 2026-10-15 with the Steam Machine cabled straight into the Deck dock's ethernet
(`enp4s0f3u1u4c2`, a USB AX88179A — it re-enumerates on replug, so restart dnsmasq if it does).

1. **Netboot image.** A throwaway flake (not under `modules/` — import-tree would load it) with
   `nixos/modules/installer/netboot/netboot-minimal.nix` from this flake's nixpkgs, plus
   `systemd.services.sshd.wantedBy = mkForce [ "multi-user.target" ]` and nixdeck's root pubkey in
   `users.users.root.openssh.authorizedKeys.keys`. Build `config.system.build.kexecTree`: it gives
   `bzImage`, `initrd.gz` (~520 MB) and `kexec-boot`, whose `--command-line` (`init=/nix/store/…`) is
   the kernel cmdline. The same tree also works by kexec from a running SteamOS.
2. **Serve it** (as root on nixdeck): `nmcli device set <if> managed no` (NM drops a manual address
   ~1 min after losing carrier), `ip addr replace 10.77.0.1/24 dev <if>`, open udp 67/69 and tcp 8080
   with `nixos-firewall-tool`, `python3 -m http.server --bind 10.77.0.1 8080` over a dir holding
   `bzImage`, `initrd.gz` and a `boot.ipxe`:
   ```
   #!ipxe
   kernel http://10.77.0.1:8080/bzImage <cmdline from kexec-boot>
   initrd http://10.77.0.1:8080/initrd.gz
   boot
   ```
   and dnsmasq for DHCP + TFTP, chaining firmware PXE → `ipxe.efi` → `boot.ipxe`:
   ```bash
   dnsmasq --keep-in-foreground --log-facility=- --port=0 --log-dhcp \
     --interface=<if> --bind-interfaces --dhcp-range=10.77.0.10,10.77.0.50,1h \
     --enable-tftp --tftp-root=<dir with ipxe.efi + undionly.kpxe from pkgs.ipxe> \
     --dhcp-userclass=set:ipxe,iPXE \
     --dhcp-match=set:efi64,option:client-arch,7 --dhcp-match=set:efi64,option:client-arch,9 \
     --dhcp-boot=tag:ipxe,http://10.77.0.1:8080/boot.ipxe \
     --dhcp-boot=tag:!ipxe,tag:efi64,ipxe.efi --dhcp-boot=tag:!ipxe,tag:!efi64,undionly.kpxe
   ```
   Afterwards: `nixos-firewall-tool reset`, `nmcli device set <if> managed yes`.
3. **Boot** the Steam Machine from the firmware boot menu's UEFI **IPv4** network entry (IPv6 gets
   no answer). Secure Boot must be off — iPXE is unsigned. The installer has no Wi-Fi firmware, so
   the cable is its only link, and no internet: the whole closure must be pushed.
4. **Install**, ssh'ing in as root with nixdeck's key:
   ```bash
   # on the installer — wipes the whole drive
   wipefs -af /dev/nvme0n1
   parted -s /dev/nvme0n1 -- mklabel gpt mkpart ESP fat32 1MiB 1GiB set 1 esp on mkpart root ext4 1GiB 100%
   mkfs.fat -F 32 -n BOOT /dev/nvme0n1p1
   mkfs.ext4 -L nixos /dev/nvme0n1p2
   mount /dev/disk/by-label/nixos /mnt
   mount -o umask=077 --mkdir /dev/disk/by-label/BOOT /mnt/boot

   # on nixdeck — ~8.4 GiB, ~5 min over gigabit
   make build HOST=steammachine
   sudo NIX_SSHOPTS="-i /root/.ssh/nixbuilder-key" nix copy --no-check-sigs \
     --to 'ssh://root@<installer-ip>?remote-store=local?root=/mnt' ./result

   # on the installer
   nixos-install --root /mnt --system <store path of ./result> --no-root-passwd --no-channel-copy
   ```
   Then copy nixdeck's Wi-Fi profile to `/mnt/etc/NetworkManager/system-connections/` (mode 600),
   **deleting its `interface-name=wlo1` line**, and reboot. Partitions are addressed by label in
   `hardware.nix`, so no generated hardware config is needed (`nvme` + `xhci_pci` are what the
   hardware actually reports).
5. **First boot**: `tailscale up --hostname=steammachine`, `passwd siigna`.
