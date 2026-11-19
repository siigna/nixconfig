{ ... }:
{
  flake.modules.nixos.reversepuck =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.reversepuck ];

      # The ReversePuck dongle's CDC link is /dev/ttyACM* (root:dialout). The Deck
      # pad's usbfs node and the puck/dongle hidraw nodes need no rule here: Steam's
      # udev rules already tag 28DE devices uaccess for the seat user.
      users.users.siigna.extraGroups = [ "dialout" ];
    };
}
