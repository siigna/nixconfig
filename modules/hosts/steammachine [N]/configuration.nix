{ inputs, ... }:
{
  # Steam Machine ("fremont"): Steam on the TV, remote builder the rest of the time.
  flake.modules.nixos.steammachine =
    { pkgs, lib, ... }:
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
      # Until it lands, declare the GPU ourselves.
      jovian.hardware.has.amd.gpu = true;

      # HDMI-CEC (TV remote) goes through the ChromeOS-style EC, not the GPU. Valve's kernel
      # knows the board ({ "Valve", "Fremont", "0000:03:00.0", "Port C" } in cros-ec-cec.c;
      # mainline doesn't), but Jovian builds it without the EC transport or the CEC driver.
      # The patch makes cec-notifier pair amdgpu's unnamed connector with the EC's "Port C"
      # lookup whichever registers first; otherwise CEC silently fails when amdgpu wins.
      # Jovian's cecd (jovian.steamos.enableHdmiCecIntegration) picks up /dev/cec0.
      boot.kernelPackages = pkgs.linuxPackages_jovian;
      boot.kernelPatches = [
        {
          name = "fremont-cros-ec-cec";
          patch = ./cec-notifier-wildcard-fallback-pairing.patch;
          structuredExtraConfig = with lib.kernel; {
            CHROME_PLATFORMS = yes;
            CROS_EC = module;
            CROS_EC_LPC = module;
            MFD_CROS_EC_DEV = module;
            MEDIA_CEC_SUPPORT = yes;
            CEC_CROS_EC = module;
          };
        }
      ];

      # Never let the TV suspend this box: it is a remote builder too. With allow_standby, a
      # CEC <Standby> (TV switched off) makes cecd call logind Suspend. steamos-manager writes
      # allow_standby = true to ~/.config/cecd/config.d/99-steamos-manager.toml; cecd merges
      # /usr/share, /etc, then ~/.config, each config.d in sorted order, later keys winning,
      # so only a fragment sorting after 99-* in deck's config.d can override it.
      systemd.tmpfiles.rules = [
        "d /home/deck/.config/cecd 0755 deck users -"
        "d /home/deck/.config/cecd/config.d 0755 deck users -"
        "L+ /home/deck/.config/cecd/config.d/zz-nixos.toml - - - - ${pkgs.writeText "cecd-nixos.toml" ''
          allow_standby = false
        ''}"
      ];

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

      # siigna@nixdeck (~/.ssh/id_ed25519). Password SSH is off (builder-service).
      users.users.siigna.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG8/ddwUdjhE1upKOBd7Npu9HD3UwuwaJxHf/7A1ToRF siigna@nixdeck"
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
