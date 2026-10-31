# The ESCargot release both escargot-tool (AppImage) and escargot-tool-wine
# (Windows .exe) are pinned to.
#
# The release server has no "latest" alias (only the Edge/Stable list on its
# index page). To bump: take the newest Edge release from
# https://releases.escargot.free/, set `release`, and copy each file's line
# from that release's SHA256SUMS into `sha256`.
{ lib }:
rec {
  release = "escargot.20261031.61099a3f.48e98a";
  # File names drop the release's trailing build suffix.
  stem = lib.concatStringsSep "." (lib.take 3 (lib.splitString "." release));
  version = lib.removePrefix "escargot." stem;
  baseUrl = "https://releases.escargot.free/v/${release}";

  sha256 = {
    appimage = "a5bf0ea5297722482ac049a31dbf1f9d5e2245e00d46529a0bfee4815656b884";
    windows = "efa73f597f52b3a95ae330921f564143b91af608c12903367e2e36c9a00808d6";
  };
}
