{ ... }:
{
  flake.modules.nixos.siigna =
    { pkgs, ... }:
    {
      users.users.siigna = {
        isNormalUser = true;
        extraGroups = [
          "wheel"
          "networkmanager"
          "plugdev"
          "libvirtd"
          "docker"
          "adbusers"
          "dialout"
          "uucp"
          "scanner"
          "lp"
        ];
        packages = [ pkgs.home-manager ];
      };
    };
}
