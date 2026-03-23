{ ... }:
{
  flake.modules.nixos.steam-library =
    { ... }:
    {
      users.groups.steam-library = { };

      users.users.siigna.extraGroups = [ "steam-library" ];
      users.users.deck.extraGroups = [ "steam-library" ];

      systemd.tmpfiles.rules = [
        "d /var/lib/steam-library 2775 root steam-library -"
      ];
    };
}
