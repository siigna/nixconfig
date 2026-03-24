self: super: {
  adi1090x-plymouth = super.callPackage ./adi1090x-plymouth { };
  ar-compositor = super.callPackage ./ar-compositor { };
  breezy-desktop = super.callPackage ./breezy { };
  xreal-one-ctl = super.callPackage ./xreal-one-ctl { };
  # Downgrade alsa-ucm-conf to 1.2.8
  # https://github.com/Jovian-Experiments/Jovian-NixOS/issues/88
  #alsa-ucm-conf = super.callPackage ./alsa-ucm-conf { };
}
