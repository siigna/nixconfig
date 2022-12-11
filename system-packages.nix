{ config, pkgs, ... }:

{
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    ardour
    bind
    element-desktop
    exiftool
    figlet
    findutils
    firefox
    freecad
    google-chrome
    gimp-with-plugins
    git
    gnome.dconf-editor
    gnome.gnome-tweaks
    gnomeExtensions.fnlock-switch-thinkpad-compact-usb-keyboard
    gnomeExtensions.gsconnect
    guvcview
    htop
    imagemagick
    inkscape-with-extensions
    iotop
    jetbrains.idea-ultimate
    mergerfs
    mergerfs-tools
    mkpasswd
    mlocate
    ncdu
    neofetch
    nheko
    obs-studio
    parted
    plex-media-player
    rpmextract
    scrcpy
    screen
    spotify
    tdesktop
    tmate
    tmux
    tree
    usbutils
    vim
    wget
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };
  programs.steam.enable = true;
}

