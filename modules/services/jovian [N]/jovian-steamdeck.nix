{ ... }:
{
  # Steam Deck hardware plus nixdeck's GDM-based session flow (deck logs in from GDM
  # into gamescope; Switch to Desktop drops back to GDM). Hosts that autostart Steam
  # (steammachine) import only `jovian`.
  flake.modules.nixos.jovian-steamdeck =
    { pkgs, ... }:
    {
      # Override the jovian-stubs package so that our steamos-session-select
      # wins even inside the Steam bubblewrap, where jovian-stubs/bin is
      # prepended to PATH via the FHS profile (overriding the system PATH).
      # This replaces Steam's session switching for nixdeck's GDM flow: kill
      # gamescope so deck drops back to GDM. Kill it directly via $gamescope_pid
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

      # steamdeck_hwmon kernel module is not available in the current kernel,
      # so jupiter-fan-control always fails. Mask it to avoid switch errors.
      systemd.services.jupiter-fan-control.enable = false;

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

      users.users.deck.extraGroups = [ "nopasswdlogin" ];
    };
}
