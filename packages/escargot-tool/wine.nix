# ESCargot Tool's Windows build, run under Wine — for checking Windows-only
# behaviour without a Windows box. Same release as escargot-tool (release.nix).
#
# The .exe is a single statically linked Qt binary, not an installer. It runs
# through a symlink in the prefix, not from Z:\nix\store: Qt probes for QML
# imports beside the exe, and every miss in /nix/store makes Wine scan all of
# it for a case-insensitive match (~100 s of startup). It gets its own prefix
# (ESCARGOT_WINEPREFIX, default ~/.local/share/escargot-tool-wine) so it never
# touches ~/.wine.
# Wine maps /dev/ttyACM* to COM ports itself; dialout access comes from the
# vesc-tool module.
#
# The exe imports icuuc.dll, a Windows 10 system DLL Wine doesn't have; a stub
# (icuuc-stub.c) is copied into the prefix's system32 on every start.
{
  lib,
  fetchurl,
  writeShellApplication,
  makeDesktopItem,
  symlinkJoin,
  wineWow64Packages,
  pkgsCross,
  escargot-tool,
}:
let
  pin = import ./release.nix { inherit lib; };
  wine = wineWow64Packages.stable;

  exe = fetchurl {
    url = "${pin.baseUrl}/windows/vesc_tool-${pin.stem}-windows-x86_64.exe";
    sha256 = pin.sha256.windows;
  };

  icuuc-stub = pkgsCross.mingwW64.stdenv.mkDerivation {
    name = "icuuc-stub";
    src = ./icuuc-stub.c;
    dontUnpack = true;
    buildPhase = ''
      $CC -shared -O2 -o icuuc.dll $src
    '';
    installPhase = ''
      install -Dm444 icuuc.dll $out/icuuc.dll
    '';
  };

  launcher = writeShellApplication {
    name = "escargot-tool-wine";
    runtimeInputs = [ wine ];
    text = ''
      export WINEPREFIX="''${ESCARGOT_WINEPREFIX:-''${XDG_DATA_HOME:-$HOME/.local/share}/escargot-tool-wine}"
      export WINEDEBUG="''${WINEDEBUG:--all}"
      if [ ! -d "$WINEPREFIX/drive_c/windows/system32" ]; then
        wineboot --init
      fi
      install -m644 ${icuuc-stub}/icuuc.dll "$WINEPREFIX/drive_c/windows/system32/icuuc.dll"
      mkdir -p "$WINEPREFIX/drive_c/escargot-tool"
      ln -sfn ${exe} "$WINEPREFIX/drive_c/escargot-tool/vesc_tool.exe"
      exec wine 'C:\escargot-tool\vesc_tool.exe' "$@"
    '';
  };

  desktopItem = makeDesktopItem {
    name = "escargot-tool-wine";
    desktopName = "ESCargot Tool (Windows/Wine)";
    exec = "escargot-tool-wine";
    icon = "${escargot-tool}/share/icons/hicolor/scalable/apps/escargot-tool.svg";
    categories = [ "Development" ];
  };
in
symlinkJoin {
  name = "escargot-tool-wine-${pin.version}";
  paths = [
    launcher
    desktopItem
  ];

  meta = {
    description = "ESCargot fork of VESC Tool, Windows build under Wine";
    homepage = "https://releases.escargot.free/";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "escargot-tool-wine";
  };
}
