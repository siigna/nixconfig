# steammachine notes

Steam Machine (codename `fremont`, Valve "Fremont" DMI) on the TV: boots straight into gaming mode
as `deck`, and is nixdeck's remote builder (`nixbuild.nix`, ahead of nixbuild.net).

Hardware as installed: AMD Custom CPU 1772 (12 threads), Navi 33 GPU, 16 GB RAM, 512 GB Kingston
NVMe (`nvme0n1`), Realtek RTL8111 ethernet (`enp5s0`), Qualcomm WCN6855 Wi-Fi (`wlp6s0`, ath11k).

**No Jovian device module yet.** Two open upstream PRs add `jovian.devices.steammachine`:
Jovian-Experiments/Jovian-NixOS#584 (duckysocks22) and #598 (K900, WIP as of 2026-10-23;
`linux-firmware-holo`, fwupd BIOS updates via `fremont-hw-support`, and `enableLightbarControl`,
which makes `/sys/class/leds/*` group-writable for `users` — check it against the `lightbar`
daemon). Until one merges, the host sets `jovian.hardware.has.amd.gpu` and
`jovianPackages.linuxPackages` itself. Once it lands: replace both with
`jovian.devices.steammachine.enable = true;` (which defaults to the Jovian kernel) — but keep the
CEC `boot.kernelPatches` entry until Jovian's kernel enables those options itself (the follow-up
`hdmi_cec` work, in neither PR).

**Jovian packages live in a scope** (`pkgs.jovianPackages.*`, since Jovian #594, 2026-10-18).
Overrides of Jovian packages must go through `jovianPackages.overrideScope`; a top-level
`jovian-stubs = prev.jovian-stubs...` overlay still evaluates but nothing reads it.

**HDMI-CEC (TV remote).** CEC is handled by the board's ChromeOS-style EC (`cros_ec_lpcs`, platform
device `cros-ec-cec.*`), not by amdgpu. Only Valve's kernel source maps the board in
`cros-ec-cec.c` (`{ "Valve", "Fremont", "0000:03:00.0", "Port C" }`); mainline's table is Google
Chromeboxes only, so mainline can't work even with the driver enabled. Jovian's kernel ships without
`CROS_EC_LPC`/`CEC_CROS_EC`, so the host adds them via `boot.kernelPatches` together with
`cec-notifier-wildcard-fallback-pairing.patch` (vendored from duckysocks22/Jovian-NixOS `hdmi_cec`
@ `10befd36`). Without the patch, pairing depends on module load order: amdgpu registers its HDMI
connector unnamed, the EC looks up "Port C", and if amdgpu registers first the two never pair and
CEC silently does nothing. That kernel config has no binary cache, so a nixpkgs/Jovian bump means a
full kernel compile. `cecd` and steamos-manager's CEC hooks come from Jovian's
`jovian.steamos.enableHdmiCecIntegration` (on by default). The TV needs Anynet+ (Samsung's CEC) on.
Verified 2026-10-15: physical address 2.0.0.0 (TV HDMI 2), OSD name "Steam Machine"; the Samsung
remote's arrows/OK/Back arrive on `cecd cros-ec-cec` as KEY_UP/DOWN/LEFT/RIGHT/ENTER/ESC.

**TV-off must not suspend the box** (it's the builder). steamos-manager writes
`allow_standby = true` into `~deck/.config/cecd/config.d/99-steamos-manager.toml`, which makes cecd
call logind Suspend on a CEC `<Standby>`. cecd merges `/usr/share/cecd`, `/etc/cecd`, then
`~/.config/cecd` (each `config.toml` then sorted `config.d/*.toml`, later keys win), so the override
is a tmpfiles symlink `zz-nixos.toml` in deck's `config.d` — `/etc/cecd` would lose. Check with
`busctl --user introspect com.steampowered.CecDaemon1 /com/steampowered/CecDaemon1/Daemon` as deck
(`AllowStandby false`). `wake_tv` stays on.

**Volume.** The TV remote's volume keys drive the TV's own speakers directly and work. Steam-side
volume → TV over CEC needs `cec-audio-control` (an `org.pipewire.ExternalVolume` varlink backend),
which needs PipeWire external-volume support that nixpkgs' PipeWire (1.6.8) lacks; upstream Jovian
also skips it ("ship this once the pipewire side is ready").

**Session flow differs from nixdeck.** nixdeck logs `deck` in from GDM (`jovian-steamdeck`).
steammachine is SteamOS-style: `jovian.steam.autoStart` (SDDM autologin with relogin) into gaming
mode, `desktopSession = "plasma"`, Plasma 6 enabled (plus X11, because `holo-session-select` maps the
bare `plasma` name to `plasmax11.desktop`). It does not import `nixos-base` (GNOME/GDM/printing).
- Switch to Desktop goes through steamos-manager's `SessionManagement1`: it writes the one-shot SDDM
  override `/etc/sddm.conf.d/zzt-holo-temp-login.conf` (`Session=plasma.desktop`) and ends the
  gamescope session; the *running* SDDM (not restarted) reads it on relogin. Before Plasma existed
  this stranded the box at the greeter. Jovian's DM-start failsafe deletes the old file name only, so
  the host also deletes `zzt-holo-temp-login.conf` in `ExecStartPre` (covers reboots).
- steamos-manager validates the desktop session against the `*-desktops/share` path in its
  `XDG_DATA_DIRS`, fixed at session start. After adding/removing a desktop, restart `user@1000` (not
  just SDDM), or `jovian-setup-desktop-session` fails with "Invalid desktop session".
- In Steam's sandbox `jovian-stubs/bin` is first on PATH; the host links `steamos-session-select`
  there to `holo-session-select` (→ `steamosctl`), so "gamescope" really returns to gaming mode.
- Desktop mode autostarts `steam -silent` (KDE-only XDG autostart) so Steam Input drives the
  controller there; a "Return to Gaming Mode" menu entry runs `steamosctl switch-to-game-mode`
  (logging out of Plasma also returns).

**Streaming apps** come from the `tv-apps` module (`plex-htpc`, Chrome kiosk launchers
`tv-youtube`/`tv-netflix`/`tv-prime`, each with a .desktop entry). They're added to the Steam library
by hand once, via desktop-mode Steam's "Add a Non-Steam Game".

**Builder.** `builder-service` accepts nixdeck's root key (`/root/.ssh/nixbuilder-key`, named for
the retired Proxmox VM) as both `nix-ssh` and `root`, via `builder.authorizedKeys`.
`nix.daemonCPUSchedPolicy`/`IOSchedClass` are `idle` so builds yield to games. That yields CPU, not
memory, so `cores = 4`, `max-jobs = 3`: at the defaults bambu-studio or a kernel build filled 16 GB
and earlyoom killed compilers and part of the deck session. siigna@nixdeck's key is also on
`nix-ssh` (not root) for `make build`'s `--build-host`; `nix-ssh`'s home is `/var/lib/nix-ssh`
because that build leaves its `result` link in the remote cwd.

**Networking.** Wi-Fi only in normal use. The NetworkManager profile (with PSK) was copied from
nixdeck at install time into `/etc/NetworkManager/system-connections/`; it is deliberately not in
the repo. `tailscale up` was run once by hand; the node is `steammachine` on the tailnet.

**Never sleeps.** On 2026-10-15 Steam's idle timer suspended the box (journal: Steam logs
"Closing timeline on system suspend" right before logind's suspend; logind's own IdleAction is
`ignore`). Steam's idle settings are per-user UI state, so suspend is refused at the bottom instead:
`systemd.sleep.settings.Sleep` sets `AllowSuspend`/`Hibernation`/`HybridSleep`/
`SuspendThenHibernate` to `no` (logind then answers `CanSuspend=no` and rejects every request,
including deliberate ones), suspend/hibernate keys are `ignore`, and Wi-Fi power saving is off. TV-off
is covered separately by cecd's `allow_standby = false` (see HDMI-CEC). Whether it comes back after a
power cut is a BIOS setting, not something NixOS controls.

**Light bar.** Driven by the `lightbar` module (`steammachine.lightbar.mode`: `meter` default,
`build`, `fixed`, `off`; `sudo lightbar mode <m>` overrides until reboot, `lightbar reset`). One
root daemon (`lightbar.py`) writes only changed LEDs and restores the shipped breathing blue on stop.
Build mode keys off processes owned by `nixbld*` users; failures aren't visible on the builder side.
Hardware details: Valve's `leds-valve` driver
(`drivers/leds/rgb/leds-valve.c`, not in mainline; `LEDS_VALVE = module` in Jovian's kernel) loads on
the `Valve`/`Fremont` DMI match and exposes the 17-LED strip as `/sys/class/leds/valve-leds[0..16]`,
each a multicolor LED (`brightness`, `multi_intensity` = "R G B"). Strip-wide attributes, present on
every index: `effect` (`patrol breath factory normal off rainbow demo manual`; per-LED colours only
show in `manual`), `enabled`, `delay` (0–20), `breath_offset`, `breath_level`, `patrol_num`,
`color_shift`, `brightness_scale` (BIOS default 56), and `brightness_startup` /
`multi_intensity_startup` (persisted to the EC). Shipped state: `breath`, `1 90 255`. All root-only;
the PR author's `led_control` branch chmods them to group `users` (presumably for Steam).
- `status:white` (`steamdeck-leds`, VLV0100) is Deck code reused here: `led_brightness_multiplier`
  is 0, and even raised to 100 a blink showed nothing visible. Treat it as not wired.
- The power-button light (white; firmware shows colours in its boot menu) is EC-driven. The driver
  only defines a power-button *brightness* register (`0xe7a`) it never exposes; a full-strip
  red/green/blue test didn't change it. No colour control from Linux.

**Monitoring.** `atop` module: raw logs every 60 s in `/var/log/atop` (28 days), process accounting
on. `atop-hourly-report.timer` (:02) writes the previous hour's `atopsar` report to
`/var/lib/atop-reports/<YYYYMMDD>/<HH>.txt`, `latest.txt` being a copy (static-web-server 403s
symlinks). Browse at `http://steammachine:8088/` over Tailscale; port 8088 isn't opened on the LAN.

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
