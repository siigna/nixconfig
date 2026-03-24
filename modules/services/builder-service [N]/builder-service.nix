{ ... }:
{
  flake.modules.nixos.builder-service =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      options.nixbuilder.authorizedKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          SSH public keys authorized to connect as nix-ssh (for remote builds)
          and as root (for nixos-rebuild --target-host administration).
        '';
      };

      config = {
        networking.hostName = "nixbuilder";
        networking.useDHCP = lib.mkDefault true;

        boot.loader.grub.enable = true;

        services.openssh = {
          enable = true;
          settings = {
            PasswordAuthentication = false;
            PermitRootLogin = "prohibit-password";
          };
        };

        # Dedicated unprivileged user the nix daemon on nixdeck SSHes in as.
        # Must be in nix.settings.trusted-users so it can accept build requests.
        users.users.nix-ssh = {
          isSystemUser = true;
          group = "nix-ssh";
          shell = pkgs.bash;
          openssh.authorizedKeys.keys = config.nixbuilder.authorizedKeys;
        };
        users.groups.nix-ssh = { };

        # Root access for nixos-rebuild --target-host and initial setup.
        users.users.root.openssh.authorizedKeys.keys = config.nixbuilder.authorizedKeys;

        nix.settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          trusted-users = [
            "root"
            "nix-ssh"
          ];
          # Let the builder fetch missing substitutes itself rather than
          # requiring nixdeck to upload every closure dependency.
          builders-use-substitutes = true;
        };

        nix.gc = {
          automatic = true;
          dates = "04:30";
          options = "-d";
          randomizedDelaySec = "15min";
        };

        security.sudo.wheelNeedsPassword = false;

        system.stateVersion = "24.11";
      };
    };
}
