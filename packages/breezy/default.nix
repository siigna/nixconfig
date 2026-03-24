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
