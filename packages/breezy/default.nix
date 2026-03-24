# Top-level breezy-desktop package.
#
# The monorepo contains two independently buildable components:
#   - XRLinuxDriver (C/Rust daemon + CLI)        → xrlinuxdriver.nix
#   - breezy-desktop GNOME UI + extension        → breezy-gnome.nix
#
# Both components live in the same upstream repo and must be built from the
# same source tree (the GNOME extension copies files from sibling modules at
# build time). The `source` attrset is constructed here and passed into both
# callPackage calls so the repo is fetched only once.
#
# The final output is a symlinkJoin so consumers get one package with all
# binaries, the extension, udev rules, and the systemd unit in a single store
# path. `extensionUuid` is re-exported for NixOS module consumers that need
# to reference the extension by UUID.
{
  symlinkJoin,
  callPackage,
  fetchgit,
}:
let
  source = {
    pname = "breezy-desktop";
    version = "v2.9.11";
    src = fetchgit {
      url = "https://github.com/wheaney/breezy-desktop";
      rev = "v2.9.11";
      fetchSubmodules = true;
      deepClone = false;
      leaveDotGit = false;
      sparseCheckout = [ ];
      sha256 = "sha256-tJDcmEOZc/rxzFO1eqAtyXf6g10ePLBh2l/dIRL/PYQ=";
    };
  };
  xrlinuxdriver = callPackage ./xrlinuxdriver.nix { inherit source; };
  breezy-gnome = callPackage ./breezy-gnome.nix { inherit xrlinuxdriver source; };
in
symlinkJoin {
  name = "breezy-desktop";
  paths = [
    breezy-gnome
    xrlinuxdriver
  ];

  passthru = {
    inherit (breezy-gnome) extensionUuid;
  };
}
