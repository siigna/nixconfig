{ inputs, ... }:
let
  # Same module over different Jovian trees: `jovian` tracks master, `jovian-fremont` the
  # steammachine PR (flake input jovian-nixos-fremont). A host imports exactly one of them.
  mkJovian =
    src:
    { pkgs, ... }:
    {
      imports = [ (src + "/modules") ];

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
          # Not oneshot: the target is ordered after the units it wants, so a 90 s oneshot kept
          # gamescope-session.target "starting" that long, and steamos-manager's Switch to
          # Desktop failed meanwhile (TransactionIsDestructive).
          Type = "simple";
          ExecStart = pkgs.writeShellScript "steam-launch-watchdog" ''
            sleep 90
            if ! systemctl --user is-active --quiet steam-launcher.service; then
              echo "steam-launch-watchdog: steam-launcher not active after 90s, terminating session"
              systemctl --user stop gamescope-session.target
            fi
          '';
        };
      };

      # No declared password: the repo is public. mutableUsers keeps whatever `passwd deck` set;
      # a fresh install leaves deck without one (autologin doesn't need it) until it's set by hand.
      users.users.deck = {
        isNormalUser = true;
        shell = pkgs.bash;
        extraGroups = [
          "networkmanager"
        ];
      };
    };
in
{
  flake.modules.nixos.jovian = mkJovian inputs.jovian-nixos;
  flake.modules.nixos.jovian-fremont = mkJovian inputs.jovian-nixos-fremont;
}
