# ReversePuck — turns the Steam Deck's built-in controls into a Steam Controller 2,
# relayed over 2.4 GHz by an nRF52840 running ReversePuckFirmware (28DE:1302) to an
# OpenPuck. Only the Deck-side Python app and the hidraw pairing tool are packaged;
# the firmware is built with arduino-cli from the same repo.
#
# Upstream's `ReversePuck` launcher bootstraps uv and downloads its own Python and
# pygame wheels, which don't run on NixOS (stub-ld), so the wrappers here use a
# nixpkgs Python instead.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  python3,
  ...
}:
let
  python = python3.withPackages (p: [
    p.pyserial
    p.pygame
    p.pyusb
  ]);
in
stdenvNoCC.mkDerivation {
  pname = "reversepuck";
  version = "0.9.67-unstable-2026-11-18";

  src = fetchFromGitHub {
    owner = "safijari";
    repo = "openpuck";
    rev = "0020aa674a73b5f38fc5e9792601da485ab0b623";
    hash = "sha256-rHJWIFaUgf2ewUkdQSqztvMe2nGYOV7MxFAWWW+LbwA=";
  };

  # Upstream scpair.py's `pair` with no --controller-serial picks the first wired
  # controller in hidraw order, which on a Deck is the built-in pad (28DE:1205): it
  # would get a useless bond plus a reboot-to-wireless. `list` also crashes on it.
  # Drop once fixed upstream.
  patches = [ ./scpair-deck-pad.patch ];

  nativeBuildInputs = [ makeWrapper ];

  # The repo's top-level Makefile builds the firmware (arduino-cli).
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/reversepuck $out/bin
    cp ReversePuck/*.py ReversePuck/README.md $out/share/reversepuck/

    # openctrl.py logs to ./openctrl.log by default; the store is read-only.
    # A later --logfile on the command line still wins (argparse keeps the last).
    makeWrapper ${python}/bin/python3 $out/bin/reversepuck \
      --add-flags "$out/share/reversepuck/openctrl.py" \
      --run 'mkdir -p "''${XDG_STATE_HOME:-$HOME/.local/state}/reversepuck"' \
      --add-flags '--logfile "''${XDG_STATE_HOME:-$HOME/.local/state}/reversepuck/openctrl.log"'

    makeWrapper ${python}/bin/python3 $out/bin/scpair \
      --add-flags "$out/share/reversepuck/scpair.py"
    runHook postInstall
  '';

  meta = {
    description = "Use the Steam Deck's controls as a Steam Controller 2 via an OpenPuck";
    homepage = "https://github.com/safijari/openpuck/tree/main/ReversePuck";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "reversepuck";
  };
}
