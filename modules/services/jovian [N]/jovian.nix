{ inputs, ... }:
{
  flake.modules.nixos.jovian =
    { pkgs, ... }:
    {
      imports = [ (inputs.jovian-nixos + "/modules") ];

      # Override the jovian-stubs package so that our steamos-session-select
      # wins even inside the Steam bubblewrap, where jovian-stubs/bin is
      # prepended to PATH via the FHS profile (overriding the system PATH).
      # The stub calls steamosctl switch-to-desktop-mode which hangs because
      # the SessionManagement1 D-Bus interface is absent in Jovian's
      # steamos-manager.  Instead, kill gamescope directly via $gamescope_pid
      # (set by the old gamescope-shim) or fall back to stopping the
      # gamescope-session.target unit (used by the newer gamescope-session).
      nixpkgs.overlays = [
        (self: super: {
          jovian-stubs = super.jovian-stubs.overrideAttrs (old: {
            buildCommand =
              let
                script = self.writeShellScript "steamos-session-select" ''
                  session="''${1:-gamescope}"
                  mkdir -p ~/.local/state
                  printf '%s\n' "$session" > ~/.local/state/steamos-session-select
                  if [[ "$session" == "plasma" ]]; then
                    if [[ -n "$gamescope_pid" ]]; then
                      kill "$gamescope_pid"
                    else
                      systemctl --user stop gamescope-session.target
                    fi
                  fi
                '';
              in
              old.buildCommand + "\ninstall -D -m 755 ${script} $out/bin/steamos-session-select\n";
          });
        })
      ];

      environment.systemPackages = with pkgs; [
        jupiter-dock-updater-bin
        steamdeck-firmware
      ];

      jovian.devices.steamdeck.enable = true;
      jovian.steam.enable = true;
      jovian.decky-loader.enable = true;

      # The Jovian default user is "decky" (a system user with nologin shell).
      # On SteamOS, UNPRIVILEGED_USER is "deck". The XRGaming plugin uses
      # `su -l $DECKY_USER` to manage xr-driver, which fails with nologin.
      # Setting user to "deck" matches SteamOS and lets the plugin manage
      # xr-driver as the actual Steam user.
      jovian.decky-loader.user = "deck";

      # The XRGaming plugin calls `su -l -c '...' deck` to manage xr-driver.
      # On NixOS, /run/wrappers/bin/su requires a TTY, but the decky-loader
      # systemd service has none. `runuser` works from root without a TTY,
      # so our `su` wrapper delegates to it.
      jovian.decky-loader.extraPackages = with pkgs; [
        (writeShellScriptBin "su" ''exec ${util-linux}/bin/runuser "$@"'')
        bash
      ];

      # Enable the vkBasalt Vulkan layer inside gamescope so the Breezy
      # XR shader (Sombrero) is active during gaming. Jovian doesn't set
      # the SteamDeck env var that SteamOS uses, so we use ENABLE_VKBASALT.
      jovian.steam.environment.ENABLE_VKBASALT = "1";

      nixpkgs.config.allowUnfree = true;
      services.pulseaudio.enable = false;

      # steamdeck_hwmon kernel module is not available in the current kernel,
      # so jupiter-fan-control always fails. Mask it to avoid switch errors.
      systemd.services.jupiter-fan-control.enable = false;

      # Decky Loader requires CEF remote debugging to inject into the Steam UI.
      # Steam only picks this up at launch, so the file must exist beforehand.
      # (Removing the file later doesn't disable it — Steam caches the state.)
      systemd.services.steam-cef-debug = {
        description = "Enable Steam CEF remote debugging for Decky Loader";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = "deck";
          ExecStart = "/bin/sh -c 'mkdir -p ~/.steam/steam && touch ~/.steam/steam/.cef-enable-remote-debugging'";
        };
      };

      # If steam-launcher hasn't come up within 90 seconds of gamescope
      # starting, assume something went wrong and kill the session so the
      # user lands back at GDM and can retry cleanly.
      systemd.user.services.steam-launch-watchdog = {
        description = "Terminate gamescope session if Steam fails to start";
        after = [ "gamescope-session.service" ];
        partOf = [ "gamescope-session.target" ];
        wantedBy = [ "gamescope-session.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "steam-launch-watchdog" ''
            sleep 90
            if ! systemctl --user is-active --quiet steam-launcher.service; then
              echo "steam-launch-watchdog: steam-launcher not active after 90s, terminating session"
              systemctl --user stop gamescope-session.target
            fi
          '';
        };
      };

      # Pin deck's GDM session to gamescope-wayland so it doesn't fall back to
      # GNOME when no session preference has been stored by AccountsService.
      system.activationScripts.deckGdmSession = ''
        mkdir -p /var/lib/AccountsService/users
        cat > /var/lib/AccountsService/users/deck << 'EOF'
[User]
Session=gamescope-wayland
SystemAccount=false
EOF
      '';

      users.users.deck = {
        hashedPassword = "REDACTED";
        isNormalUser = true;
        shell = pkgs.bash;
        extraGroups = [ "networkmanager" "nopasswdlogin" ];
      };

      # The XRGaming plugin deletes LD_LIBRARY_PATH from the subprocess env
      # before running install steps, assuming it was inherited from Steam.
      # The Decky service doesn't have it, so the deletion crashes with KeyError.
      # Setting it empty satisfies the del without affecting anything.
      systemd.services.decky-loader.environment.LD_LIBRARY_PATH = "";
    };
}
