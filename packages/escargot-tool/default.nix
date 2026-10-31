# ESCargot Tool — our VESC Tool fork, as the AppImage from releases.escargot.free.
# The release is pinned in release.nix, shared with escargot-tool-wine.
#
# Installed as escargot-tool so it can sit beside nixpkgs' vesc_tool.
{
  lib,
  appimageTools,
  fetchurl,
}:
let
  pin = import ./release.nix { inherit lib; };
  pname = "escargot-tool";
  inherit (pin) version;

  src = fetchurl {
    url = "${pin.baseUrl}/linux/vesc_tool-${pin.stem}-x86_64.AppImage";
    sha256 = pin.sha256.appimage;
  };

  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm444 ${contents}/escargot-tool.desktop $out/share/applications/escargot-tool.desktop
    substituteInPlace $out/share/applications/escargot-tool.desktop \
      --replace-fail 'Exec=vesc_tool' 'Exec=escargot-tool'
    install -Dm444 ${contents}/usr/share/icons/hicolor/scalable/apps/escargot-tool.svg \
      $out/share/icons/hicolor/scalable/apps/escargot-tool.svg
  '';

  meta = {
    description = "ESCargot fork of VESC Tool (prebuilt AppImage)";
    homepage = "https://releases.escargot.free/";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "escargot-tool";
  };
}
