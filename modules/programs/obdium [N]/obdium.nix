{ ... }:
{
  flake.modules.nixos.obdium =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.obdium ];

      # Grant non-root access to ELM327 USB-serial adapters (/dev/ttyUSB*).
      users.users.siigna.extraGroups = [ "dialout" ];
    };
}
