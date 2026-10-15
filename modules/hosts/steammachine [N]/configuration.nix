{ inputs, ... }:
{
  # Steam Machine ("fremont"): Steam on the TV, remote builder the rest of the time.
  flake.modules.nixos.steammachine =
    { pkgs, ... }:
    {
      imports = with inputs.self.modules.nixos; [
        nixos-common
        hardware-steammachine
        hosts-file
        jovian
        tailscale
        builder-service
        siigna
      ];

      networking.hostName = "steammachine";

      # Boot straight into gaming mode as deck (SDDM autologin, relogin on exit).
      # No desktop session: Switch to Desktop relaunches gaming mode.
      jovian.steam = {
        autoStart = true;
        user = "deck";
        desktopSession = "gamescope-wayland";
      };
      # Pushes desktopSession into steamos-manager, which rejects gamescope-wayland
      # ("Invalid desktop session") and leaves a failed unit. Nothing to set without a desktop.
      systemd.user.services.jovian-setup-desktop-session.enable = false;

      # Jovian has no jovian.devices.steammachine yet (PR Jovian-Experiments/Jovian-NixOS#584).
      # Until it lands, declare the GPU ourselves and run a current mainline kernel.
      jovian.hardware.has.amd.gpu = true;
      boot.kernelPackages = pkgs.linuxPackages_latest;

      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
      };

      hardware.xpadneo.enable = true;

      # nixdeck's root key (/root/.ssh/nixbuilder-key), used by its nix daemon (nixbuild module)
      # and for nixos-rebuild --target-host.
      builder.authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ+zOqWYTT9i14P/8mbeD+hpazV7JlBCyWuHFhMrP3Bx root@nixdeck"
      ];

      # Remote builds must not stutter a game on the TV.
      nix.daemonCPUSchedPolicy = "idle";
      nix.daemonIOSchedClass = "idle";

      environment.systemPackages = with pkgs; [
        git
        htop
        vim
      ];

      system.stateVersion = "26.11";
    };
}
