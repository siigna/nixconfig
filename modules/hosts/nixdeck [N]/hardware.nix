{ ... }:
{
  flake.modules.nixos.hardware-nixdeck =
    { config, lib, modulesPath, ... }:
    {
      imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

      boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "usbhid" "sdhci_pci" ];
      boot.initrd.kernelModules = [ ];
      boot.kernelModules = [ "kvm-amd" ];
      boot.extraModulePackages = [ ];

      fileSystems."/" = {
        device = "/dev/disk/by-uuid/deb0588b-0952-4168-8448-4d1391621aeb";
        fsType = "ext4";
      };

      fileSystems."/boot" = {
        device = "/dev/disk/by-uuid/1F0E-3414";
        fsType = "vfat";
      };

      fileSystems."/mnt/win" = {
        device = "/dev/disk/by-uuid/2086FDAB86FD8218";
        fsType = "lowntfs-3g";
        options = [ "rw" "uid=1000" "gid=100" "user" "exec" "umask=000" ];
      };

      swapDevices = [ { device = "/dev/disk/by-uuid/716413ae-f194-4ad1-a163-ab5da7652ae1"; } ];

      networking.useDHCP = lib.mkDefault true;

      hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    };
}
