# hardware-nixbuilder notes

nixpkgs' `virtualisation/proxmox-image.nix` defines the root filesystem, `boot.growPartition` and
virtio initrd modules — but only while `build-image` is running. A plain evaluation of
`.#nixosConfigurations.nixbuilder` therefore used to fail with *"The 'fileSystems' option does not
specify your root file system"*, which blocked `nixos-rebuild switch --flake .#nixbuilder
--target-host root@nixbuilder` against the live VM.

The virtio modules are the bigger trap: the default `boot.initrd.availableKernelModules` in
`system/boot/kernel.nix` contains no virtio driver at all, so a system built outside the image path
would produce an initrd that cannot see `/dev/vda` — an unbootable VM.

`hardware.nix` declares the real hardware (`/dev/disk/by-label/nixos`, ext4, autoResize). Everything
the image module also sets is `lib.mkDefault`, and `/boot` is deliberately **not** declared — the
host uses BIOS GRUB on `/dev/vda`, there is no ESP, and mounting a nonexistent one would break boot.
