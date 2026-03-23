self: super:
{
  adi1090x-plymouth = super.callPackage ./adi1090x-plymouth { };
  breezy-desktop = super.callPackage ./breezy { };
  # Downgrade alsa-ucm-conf to 1.2.8
  # https://github.com/Jovian-Experiments/Jovian-NixOS/issues/88
  #alsa-ucm-conf = super.callPackage ./alsa-ucm-conf { };
}

