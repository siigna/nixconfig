# HID Global Fargo DTC4250e CUPS printer driver v1.0.0.4
#
# Proprietary binary driver — ships rastertofargo-3.3.4 filter + DTC4250e.ppd.
# Wrapper script sets LD_LIBRARY_PATH for libcups/libcupsimage — avoids
# patchelf ELF rewriting which corrupts this binary's symbol version table.
# PPD hardcoded /usr/share paths are rewritten to nix store $out paths.
{
  stdenv,
  cups,
  patchelf,
  lib,
  requireFile,
}:
stdenv.mkDerivation {
  pname = "fargo-dtc4250e-driver";
  version = "1.0.0.4";

  # requireFile rather than a path or fetchurl: HID gates the download behind a
  # form, and an absolute path out of ~/Downloads forces `nixos-rebuild --impure`
  # for the whole flake. Add the tarball to the store once per machine with the
  # command printed in `message` below.
  src = requireFile {
    name = "DTC4250e-1.0.0.4-x64.tar.gz";
    hash = "sha256-y2ZsEDzVyuUqBvLBEQ723j/EsiYdsunp7OYb0HY6as0=";
    url = "https://www.hidglobal.com/drivers";
    message = ''
      The HID Fargo DTC4250e Linux driver is not redistributable and must be
      fetched by hand from HID Global:

        https://www.hidglobal.com/drivers

      Download "SFW-02132 Rev B - DTC4250e Linux Printer Driver v1.0.0.4",
      unpack the outer archive, then add the x64 tarball to the store:

        nix-store --add-fixed sha256 DTC4250e-1.0.0.4-x64.tar.gz
    '';
  };

  nativeBuildInputs = [ patchelf ];
  buildInputs = [ cups ];

  dontUnpack = false;
  dontBuild = true;

  unpackPhase = ''
    tar -xzf $src
  '';

  installPhase = ''
    # Filter binary — patch interpreter only; rpath left alone (LD_LIBRARY_PATH handles libs)
    # --set-rpath combined with --set-interpreter corrupts this binary's symbol version table
    install -Dm755 usr/lib/cups/filter/rastertofargo-3.3.4 \
      $out/lib/cups/filter/rastertofargo-3.3.4.real
    patchelf \
      --set-interpreter "$(cat ${stdenv.cc}/nix-support/dynamic-linker)" \
      $out/lib/cups/filter/rastertofargo-3.3.4.real

    # Wrapper script: sets LD_LIBRARY_PATH for cups + gcc C++ runtime, then execs real binary
    cat > $out/lib/cups/filter/rastertofargo-3.3.4 << EOF
    #!${stdenv.shell}
    export LD_LIBRARY_PATH="${lib.makeLibraryPath [ cups stdenv.cc.cc ]}\''${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
    exec "$out/lib/cups/filter/rastertofargo-3.3.4.real" "\$@"
    EOF
    chmod 755 $out/lib/cups/filter/rastertofargo-3.3.4

    # PPD — rewrite hardcoded /usr/share paths to nix store $out paths
    install -Dm644 usr/share/cups/model/DTC4250e.ppd \
      $out/share/cups/model/DTC4250e.ppd
    substituteInPlace $out/share/cups/model/DTC4250e.ppd \
      --replace '"/usr/share/fargo/DTC4250e/DTC4250e.xml"' '"'"$out"'/share/fargo/DTC4250e/DTC4250e.xml"' \
      --replace '"/usr/share/cups/profiles/dtc4250eCLR.icm"' '"'"$out"'/share/cups/profiles/dtc4250eCLR.icm"' \
      --replace '"/usr/share/cups/profiles/dtc4250eCLR_L.icm"' '"'"$out"'/share/cups/profiles/dtc4250eCLR_L.icm"'

    # ICC profiles (Linux driver)
    install -Dm644 usr/share/cups/profiles/dtc4250eCLR.icm \
      $out/share/cups/profiles/dtc4250eCLR.icm
    install -Dm644 usr/share/cups/profiles/dtc4250eCLR_L.icm \
      $out/share/cups/profiles/dtc4250eCLR_L.icm

    # Additional ICC profile from Windows driver (newer, HID-specific gamut)
    install -Dm644 ${./extras/CLR_HID_D001.icm} \
      $out/share/cups/profiles/dtc4250eCLR_HID_D001.icm

    # Raw test print jobs from Windows driver — send via: nc 172.31.5.2 9100 < file.prn
    for prn in ${./extras}/*.prn; do
      install -Dm644 "$prn" "$out/share/fargo/DTC4250e/test/$(basename $prn)"
    done

    # Printer XML config
    install -Dm644 usr/share/fargo/DTC4250e/DTC4250e.xml \
      $out/share/fargo/DTC4250e/DTC4250e.xml

    # Udev rules
    install -Dm644 etc/udev/rules.d/92-fargo.rules \
      $out/lib/udev/rules.d/92-fargo.rules
  '';

  meta = {
    description = "HID Global Fargo DTC4250e Linux CUPS printer driver";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
}
