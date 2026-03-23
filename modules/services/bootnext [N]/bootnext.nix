{ ... }:
{
  flake.modules.nixos.bootnext =
    { pkgs, ... }:
    {
      systemd.services.bootnext-steamos = {
        description = "Set UEFI BootNext to SteamOS";
        wantedBy = [ "multi-user.target" ];
        serviceConfig.Type = "oneshot";
        script = "${pkgs.efibootmgr}/bin/efibootmgr -n $(${pkgs.efibootmgr}/bin/efibootmgr | grep BootCurrent | tr -cd [:digit:])";
      };
    };
}
