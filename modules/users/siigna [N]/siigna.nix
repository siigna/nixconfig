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
        ];
        packages = [ pkgs.home-manager ];
      };
    };
}
