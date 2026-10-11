{ inputs, ... }:
{
  flake.modules.nixos.nixbuilder =
    { lib, ... }:
    {
      imports = with inputs.self.modules.nixos; [
        hardware-nixbuilder
        builder-service
        tailscale
      ];

      networking.hostName = "nixbuilder";
      networking.useDHCP = lib.mkDefault true;
      # Force ethernet interfaces up at boot — without this, networkd leaves
      # the link down until manually upped (observed on Proxmox virtio NICs).
      systemd.network.networks."10-ethernet" = {
        matchConfig.Name = "en* eth*";
        linkConfig.ActivationPolicy = "always-up";
        networkConfig.DHCP = "yes";
      };

      boot.loader.grub.enable = true;
      # Proxmox virtio disk — used by GRUB after nixos-rebuild switch on the live VM.
      boot.loader.grub.device = "/dev/vda";
      # Serial console for Proxmox "Serial Console" tab fallback.
      # tty1 listed last so it remains the GRUB/boot default.
      boot.kernelParams = lib.mkAfter [
        "console=ttyS0,115200n8"
        "console=tty1"
      ];

      # SSH public keys allowed to:
      #   - connect as nix-ssh (used by nixdeck's nix daemon for remote builds)
      #   - connect as root (used for nixos-rebuild --target-host root@nixbuilder)
      #
      # Generate a dedicated key on nixdeck:
      #   sudo ssh-keygen -t ed25519 -f /root/.ssh/nixbuilder-key -N ""
      # Then paste the public key below:
      #   sudo cat /root/.ssh/nixbuilder-key.pub
      nixbuilder.authorizedKeys = [
        # "ssh-ed25519 AAAA... root@nixdeck"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ+zOqWYTT9i14P/8mbeD+hpazV7JlBCyWuHFhMrP3Bx root@nixdeck"
      ];

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      nix.gc = {
        automatic = true;
        dates = "04:30";
        options = "-d";
        randomizedDelaySec = "15min";
      };

      security.sudo.wheelNeedsPassword = false;

      # Local console user for bootstrap access (e.g. before tailscale is up).
      # Change password after first login: passwd admin
      # Or generate a hash to replace initialPassword: mkpasswd -m sha-512
      users.users.admin = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        initialPassword = "REDACTED";
      };

      system.stateVersion = "24.11";
    };
}
