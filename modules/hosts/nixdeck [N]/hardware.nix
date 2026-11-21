{ ... }:
{
  flake.modules.nixos.hardware-nixdeck =
    {
      config,
      lib,
      pkgs,
      modulesPath,
      ...
    }:
    {
      imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

      boot.initrd.availableKernelModules = [
        "nvme"
        "xhci_pci"
        "usbhid"
        "sdhci_pci"
      ];
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
        fsType = "ntfs3";
        options = [
          "rw"
          "uid=1000"
          "gid=100"
          "umask=000"
          "nofail"
        ];
      };

      swapDevices = [ { device = "/dev/disk/by-uuid/716413ae-f194-4ad1-a163-ab5da7652ae1"; } ];

      # The QCA Bluetooth chip on UART loses its firmware when hibernation cuts power, and
      # hci_uart doesn't reload it on resume (hci0 times out until reboot). Rebind the driver.
      # hibernate.target is only reached once systemd-hibernate.service returns, i.e. post-resume.
      systemd.services.bluetooth-reload-after-hibernate = {
        description = "Reload hci_uart after hibernate resume";
        wantedBy = [
          "hibernate.target"
          "suspend-then-hibernate.target"
        ];
        after = [
          "hibernate.target"
          "suspend-then-hibernate.target"
        ];
        serviceConfig.Type = "oneshot";
        path = [ pkgs.kmod ];
        script = "modprobe -r hci_uart && modprobe hci_uart";
      };

      networking.useDHCP = lib.mkDefault true;

      hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    };
}
