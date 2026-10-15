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

      jovian.steam.enable = true;
      jovian.decky-loader.enable = true;

      # The Jovian default user is "decky" (a system user with nologin shell).
      # On SteamOS, UNPRIVILEGED_USER is "deck". The XRGaming plugin uses
      # `su -l $DECKY_USER` to manage xr-driver, which fails with nologin.
      # Setting user to "deck" matches SteamOS and lets the plugin manage
      # xr-driver as the actual Steam user.
      jovian.decky-loader.user = "deck";

      nixpkgs.config.allowUnfree = true;
      services.pulseaudio.enable = false;

      # Decky Loader requires CEF remote debugging to inject into the Steam UI.
      # Steam only picks this up at launch, so the file must exist beforehand.
      # (Removing the file later doesn't disable it — Steam caches the state.)
      # Written to ~/.local/share/Steam, the target of the ~/.steam/steam symlink. Creating
      # ~/.steam/steam as a directory on a fresh home makes Steam's bootstrap fail with
      # "Couldn't set up Steam data", because it needs to create that path as the symlink.
      systemd.services.steam-cef-debug = {
        description = "Enable Steam CEF remote debugging for Decky Loader";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = "deck";
          ExecStart = "/bin/sh -c 'mkdir -p ~/.local/share/Steam && touch ~/.local/share/Steam/.cef-enable-remote-debugging'";
        };
      };

      # If steam-launcher hasn't come up within 90 seconds of gamescope
      # starting, assume something went wrong and kill the session so the
      # user lands back at the display manager and can retry cleanly.
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

      users.users.deck = {
        hashedPassword = "REDACTED";
        isNormalUser = true;
        shell = pkgs.bash;
        extraGroups = [
          "networkmanager"
        ];
      };
    };
}
