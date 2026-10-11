{ ... }:
{
  # Steam Deck hardware plus nixdeck's GDM-based session flow (deck logs in from GDM
  # into gamescope; Switch to Desktop drops back to GDM). Hosts that autostart Steam
  # (steammachine) import only `jovian`.
  flake.modules.nixos.jovian-steamdeck =
    { pkgs, ... }:
    {
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
