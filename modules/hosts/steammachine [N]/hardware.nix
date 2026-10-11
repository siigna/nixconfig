{ ... }:
{
  # Partitions are addressed by label so this works without a nixos-generate-config pass:
  # format the ESP with `mkfs.fat -F 32 -n BOOT` and root with `mkfs.ext4 -L nixos`.
  # Compare boot.initrd.availableKernelModules against
  # `nixos-generate-config --show-hardware-config` on the real hardware.
  flake.modules.nixos.hardware-steammachine =
    {
      config,
      lib,
      modulesPath,
      ...
    }:
    {
      imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

      boot.initrd.availableKernelModules = [
        "nvme"
        "xhci_pci"
        "ahci"
        "usbhid"
        "usb_storage"
        "sd_mod"
      ];
      boot.kernelModules = [ "kvm-amd" ];

      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
      };

      fileSystems."/boot" = {
        device = "/dev/disk/by-label/BOOT";
        fsType = "vfat";
        options = [
          "fmask=0077"
          "dmask=0077"
        ];
      };

      zramSwap.enable = true;

      networking.useDHCP = lib.mkDefault true;

      hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    };
}
