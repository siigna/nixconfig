# ESCargot Tool — our VESC Tool fork, as the AppImage from releases.escargot.free.
#
# The release server has no "latest" alias (only the Edge/Stable list on its
# index page), so this pins one release. To bump: take the newest Edge release
# from https://releases.escargot.free/, set `release`, and copy the AppImage's
# line from that release's SHA256SUMS into `sha256`.
#
# Installed as escargot-tool so it can sit beside nixpkgs' vesc_tool.
{
  lib,
  appimageTools,
  fetchurl,
}:
let
  release = "escargot.20261031.61099a3f.48e98a";
  # The AppImage name drops the release's trailing build suffix.
  stem = lib.concatStringsSep "." (lib.take 3 (lib.splitString "." release));
  pname = "escargot-tool";
  version = lib.removePrefix "escargot." stem;

  src = fetchurl {
    url = "https://releases.escargot.free/v/${release}/linux/vesc_tool-${stem}-x86_64.AppImage";
    sha256 = "a5bf0ea5297722482ac049a31dbf1f9d5e2245e00d46529a0bfee4815656b884";
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
