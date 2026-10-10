{ ... }:
{
  # Hardware for the Proxmox VM.
  #
  # `nixos-rebuild build-image --image-variant proxmox` supplies all of this
  # itself (nixpkgs' virtualisation/proxmox-image.nix), so the image built by
  # `make image-nixbuilder` never needed it. A plain evaluation of
  # .#nixosConfigurations.nixbuilder does, though — without it the config fails
  # with "The 'fileSystems' option does not specify your root file system", so
  # `nixos-rebuild switch --flake .#nixbuilder --target-host root@nixbuilder`
  # against the live VM could not work.
  #
  # The virtio modules matter beyond the assertion: the default
  # boot.initrd.availableKernelModules list has no virtio at all, so a system
  # built outside the image path would produce an initrd that cannot see
  # /dev/vda and the VM would not boot.
  #
  # Every value the image module also defines is mkDefault here so the image
  # build keeps winning and no option conflicts.
  flake.modules.nixos.hardware-nixbuilder =
    { lib, ... }:
    {
      fileSystems."/" = {
        device = lib.mkDefault "/dev/disk/by-label/nixos";
        fsType = lib.mkDefault "ext4";
        autoResize = lib.mkDefault true;
      };

      # Grow the root partition to fill the virtual disk on boot.
      boot.growPartition = lib.mkDefault true;

      # virtio_blk/virtio_scsi: the root disk, depending on how the Proxmox VM's
      # disk is attached. uas: USB passthrough. None are in the default list.
      boot.initrd.availableKernelModules = [
        "uas"
        "virtio_blk"
        "virtio_scsi"
        "virtio_pci"
      ];
    };
}
