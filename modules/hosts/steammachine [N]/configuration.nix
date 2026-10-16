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
        tv-apps
        atop
      ];

      networking.hostName = "steammachine";

      # Boot straight into gaming mode as deck (SDDM autologin, relogin on exit), SteamOS-style:
      # Switch to Desktop opens Plasma, logging out of Plasma returns to gaming mode.
      jovian.steam = {
        autoStart = true;
        user = "deck";
        desktopSession = "plasma";
      };
      # Plasma 6 (Wayland "plasma"); X11 too, since holo-session-select maps the bare "plasma"
      # session name to plasmax11.desktop.
      services.desktopManager.plasma6.enable = true;
      services.xserver.enable = true;
      # DrKonqi (KDE's crash reporter, pulled in by Plasma, not excludable) can't start inside
      # gamescope and dumps core itself, which triggers DrKonqi again: an endless coredump loop
      # after any crash in gaming mode. Nobody reads crash dialogs on a TV box; mask it.
      systemd.services."drkonqi-coredump-processor@".enable = false;
      systemd.user.sockets.drkonqi-coredump-launcher.enable = false;
      systemd.user.services."drkonqi-coredump-launcher@".enable = false;
      # As on SteamOS: Steam keeps running (tray) in desktop mode, which is what makes the Steam
      # Controller a mouse/keyboard there (Steam Input) and where "Add a Non-Steam Game" lives.
      # KDE-only so it never fires inside the gamescope session.
      environment.etc."xdg/autostart/steam-desktop-mode.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Steam (desktop mode)
        Exec=steam -silent
        OnlyShowIn=KDE;
        X-KDE-autostart-phase=2
      '';

      # Switch to Desktop: steamos-manager (SessionManagement1) writes a one-shot SDDM autologin
      # override and ends the gamescope session; the running SDDM then logs into Plasma once.
      # Jovian's failsafe deletes that override on DM start so a reboot always lands in gaming
      # mode, but under the old name (zzt-steamos-temp-login.conf); steamos-manager 26.x writes
      # zzt-holo-temp-login.conf.
      systemd.services.display-manager.serviceConfig.ExecStartPre = [
        "-${pkgs.coreutils}/bin/rm -f /etc/sddm.conf.d/zzt-holo-temp-login.conf"
      ];

      # Inside Steam's sandbox jovian-stubs/bin comes first on PATH. Give it the real
      # steamos-session-select (holo-session-select -> steamosctl), so "gamescope" switches back
      # to gaming mode. nixdeck replaces it with its own GDM stub instead (jovian-steamdeck).
      nixpkgs.overlays = [
        (final: prev: {
          jovian-stubs = prev.jovian-stubs.overrideAttrs (old: {
            buildCommand = old.buildCommand + ''
              ln -s ${final.holo-session-selection}/bin/holo-session-select $out/bin/steamos-session-select
            '';
          });
        })
      ];

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
        # App-menu entry for leaving Plasma (logging out works too).
        (makeDesktopItem {
          name = "return-to-gaming-mode";
          desktopName = "Return to Gaming Mode";
          exec = "steamosctl switch-to-game-mode";
          icon = "steam";
          categories = [ "Game" ];
        })
      ];

      system.stateVersion = "26.11";
    };
}
