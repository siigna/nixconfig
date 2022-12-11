{ config, pkgs, ... }:
{
  imports = [
      (
        let revision = "cc896be6a3ebbccf04e7e07e89b666fa091a846a"; in
        builtins.fetchTarball {
          url = "https://github.com/Jovian-Experiments/Jovian-NixOS/archive/${revision}.tar.gz";
          sha256 = "sha256:00qnhdjhdmwijdhshcqya74mg5g2x582vmzz67c0am1j9n975qxx";
        } + "/modules"
      )
    ];

  environment.systemPackages = with pkgs; [
    jupiter-dock-updater-bin
    steamdeck-firmware
  ];

  # enable the Steam Deck-specific hardware configurations
  jovian.devices.steamdeck.enable = true;

  # use the Steam Deck UI
  jovian.steam.enable = true;

  # Get around conflicting definition values
  hardware.pulseaudio.enable = false;

  # Allow unfree for steamdeck-hw-theme
  nixpkgs.config.allowUnfree = true;

  # Add a deck user
  users.users.deck = {
    hashedPassword = "REDACTED";
    isNormalUser = true;
    extraGroups = [
      "networkmanager"
      "nopasswdlogin"
    ];
  };
}
