# The ESCargot release both escargot-tool (AppImage) and escargot-tool-wine
# (Windows .exe) are pinned to.
#
# The release server has no "latest" alias (only the Edge/Stable list on its
# index page). To bump: take the newest Edge release from
# https://releases.escargot.free/, set `release`, and copy each file's line
# from that release's SHA256SUMS into `sha256`.
{ lib }:
rec {
  release = "escargot.20261101.f0be0e26.55e1ed";
  # File names drop the release's trailing build suffix.
  stem = lib.concatStringsSep "." (lib.take 3 (lib.splitString "." release));
  version = lib.removePrefix "escargot." stem;
  baseUrl = "https://releases.escargot.free/v/${release}";

  sha256 = {
    appimage = "2ae0344c9afbd712e7e52b45788ab7a44e34ef9717a9d225da608ef25e6afbd1";
    windows = "c3db343e32ecb7195e0ffc87a3a34067d687d30783db15b643907d3d963a11a9";
  };
}
