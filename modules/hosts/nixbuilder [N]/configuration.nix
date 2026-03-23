{ inputs, ... }:
{
  flake.modules.nixos.nixbuilder = {
    imports = with inputs.self.modules.nixos; [
      builder-service
      tailscale
    ];

    # SSH public keys allowed to:
    #   - connect as nix-ssh (used by nixdeck's nix daemon for remote builds)
    #   - connect as root (used for nixos-rebuild --target-host root@nixbuilder)
    #
    # Generate a dedicated key on nixdeck:
    #   sudo ssh-keygen -t ed25519 -f /root/.ssh/nixbuilder-key -N ""
    # Then paste the public key below:
    #   sudo cat /root/.ssh/nixbuilder-key.pub
    # Proxmox virtio disk — used by GRUB after nixos-rebuild switch on the live VM.
    boot.loader.grub.device = "/dev/vda";

    nixbuilder.authorizedKeys = [
      # "ssh-ed25519 AAAA... root@nixdeck"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ+zOqWYTT9i14P/8mbeD+hpazV7JlBCyWuHFhMrP3Bx root@nixdeck"
    ];
  };
}
