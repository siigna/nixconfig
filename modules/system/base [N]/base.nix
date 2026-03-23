{ inputs, ... }:
{
  flake.modules.nixos.nixos-base =
    { pkgs, lib, config, ... }:
    {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      options.nixdeck.useGrub = lib.mkEnableOption "GRUB bootloader instead of systemd-boot";

      config = {
        nixpkgs.config.allowUnfree = true;
        nixpkgs.overlays = [
          (import inputs.packages)
          inputs.claude-code-nix.overlays.default
        ];

        # TODO: migrate Tailscale auth key to agenix secrets management
        nixpkgs.config.permittedInsecurePackages = [
          "olm-3.2.16"
          "fluffychat-linux-1.23.0"
          "fluffychat-linux-1.25.1"
          "fluffychat-linux-1.26.0"
          "ventoy-1.1.05"
          "fluffychat-linux-1.26.1"
          "fluffychat-linux-1.27.0"
          "ventoy-1.1.07"
          "ventoy-1.1.10"
        ];

        boot = {
          supportedFilesystems = [ "ntfs" ];
          initrd.systemd.enable = true;
          kernelParams = [
            "quiet"
            "splash"
            "loglevel=3"
            "rd.udev.log_level=3"
            "systemd.show_status=auto"
            "boot.shell_on_fail"
            "systemd.debug-shell=1"
          ];
          loader = {
            efi.canTouchEfiVariables = true;
            timeout = 2;
            systemd-boot.enable = !config.nixdeck.useGrub;
            systemd-boot.configurationLimit = 3;
            grub = lib.mkIf config.nixdeck.useGrub {
              enable = true;
              device = "nodev";
              efiSupport = true;
            };
          };
          plymouth = {
            enable = true;
            themePackages = [ pkgs.adi1090x-plymouth ];
            theme = "lone";
          };
        };

        networking.hostName = "nixdeck";
        networking.networkmanager.enable = true;
        networking.firewall = {
          # KDE Connect / GSConnect
          allowedTCPPortRanges = [ { from = 1714; to = 1764; } ];
          allowedUDPPortRanges = [ { from = 1714; to = 1764; } ];
          # Evidence.dev dev server
          allowedTCPPorts = [ 3000 ];
        };

        time.timeZone = "America/Los_Angeles";

        services.logind.settings.Login = {
          NAutoVTs = 6;
          ReserveVT = 6;
        };

        services.xserver.enable = true;
        services.displayManager.gdm.enable = true;
        services.desktopManager.gnome.enable = true;

        # GDM monitor config: prefer XREAL glasses as primary, fall back to built-in eDP-1.
        # GDM reads /var/lib/gdm/.config/monitors.xml and matches the config whose monitor
        # set (including disabled) matches the currently connected hardware.
        systemd.tmpfiles.rules = [
          "L+ /var/lib/gdm/.config/monitors.xml - - - - ${pkgs.writeText "gdm-monitors.xml" ''
            <monitors version="2">
              <!-- XREAL One Pro connected: use as primary, disable eDP-1 -->
              <configuration>
                <layoutmode>physical</layoutmode>
                <logicalmonitor>
                  <x>0</x>
                  <y>0</y>
                  <scale>1</scale>
                  <primary>yes</primary>
                  <monitor>
                    <monitorspec>
                      <connector>DP-1</connector>
                      <vendor>MRG</vendor>
                      <product>XREAL One Pro</product>
                      <serial>0x00000000</serial>
                    </monitorspec>
                    <mode>
                      <width>1920</width>
                      <height>1080</height>
                      <rate>120.000</rate>
                    </mode>
                  </monitor>
                </logicalmonitor>
                <disabled>
                  <monitorspec>
                    <connector>eDP-1</connector>
                    <vendor>VLV</vendor>
                    <product>ANX7530 U</product>
                    <serial>0x00000001</serial>
                  </monitorspec>
                </disabled>
              </configuration>
              <!-- Fallback: eDP-1 only (glasses not connected) -->
              <configuration>
                <layoutmode>physical</layoutmode>
                <logicalmonitor>
                  <x>0</x>
                  <y>0</y>
                  <scale>1</scale>
                  <primary>yes</primary>
                  <monitor>
                    <monitorspec>
                      <connector>eDP-1</connector>
                      <vendor>VLV</vendor>
                      <product>ANX7530 U</product>
                      <serial>0x00000001</serial>
                    </monitorspec>
                    <mode>
                      <width>1280</width>
                      <height>800</height>
                      <rate>90.061</rate>
                    </mode>
                  </monitor>
                </logicalmonitor>
              </configuration>
            </monitors>
          ''}"
        ];
        services.xserver.xkb.layout = "us";
        services.flatpak.enable = true;
        services.printing.enable = true;

        hardware.bluetooth.package = pkgs.bluez;
        hardware.xpadneo.enable = true;

        environment.localBinInPath = true;
        environment.sessionVariables = {
          XDG_DATA_DIRS = [
            "/var/lib/flatpak/exports/share"
            "\${HOME}/.local/share/flatpak/exports/share"
          ];
          EDITOR = "vim";
        };

        home-manager.useUserPackages = true;
        home-manager.useGlobalPkgs = true;

        nix.gc = {
          automatic = true;
          dates = "03:15";
          options = "-d";
        };

        nix.settings = {
          experimental-features = [ "nix-command" "flakes" ];
          trusted-users = [ "root" "siigna" ];
        };

        security.sudo.wheelNeedsPassword = false;

        # https://github.com/NixOS/nixpkgs/issues/180175
        systemd.services.NetworkManager-wait-online.enable = false;

        # hidraw permissions for Teensy @ 16c0:0486
        services.udev.extraRules = ''
          ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="0486", TAG+="uaccess"
        '';

        system.stateVersion = "22.11";
      };
    };
}
