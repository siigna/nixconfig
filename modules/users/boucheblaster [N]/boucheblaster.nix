{ ... }:
{
  flake.modules.nixos.boucheblaster = {
    users.users.boucheblaster = {
      isNormalUser = true;
      extraGroups = [
        "dialout"
        "networkmanager"
        "plugdev"
        "uucp"
      ];
    };
  };
}
