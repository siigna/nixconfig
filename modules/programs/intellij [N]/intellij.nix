{ ... }:
{
  flake.modules.nixos.intellij =
    { pkgs, ... }:
    let
      # Pinned to 2022.2.5 — last release covered by perpetual fallback licence.
      # To update: grab the new hash from
      #   https://download.jetbrains.com/idea/ideaIU-<VERSION>.tar.gz.sha256
      # then convert hex→SRI:
      #   echo "<hex>" | xxd -r -p | base64 -w0
      idea = pkgs.jetbrains.idea.overrideAttrs (old: {
        version = "2022.2.5";
        src = pkgs.fetchurl {
          url = "https://download.jetbrains.com/idea/ideaIU-2022.2.5.tar.gz";
          hash = "sha256-o0OZql6aPWI5maoO/IF1qUc0sKaWVDRP5PcrAVOri6w=";
        };
        # Remove the remote-dev-server plugin directory before postPatch runs
        # so the current-nixpkgs remote-dev patch doesn't try to apply against
        # the 2022.2 source structure (we don't use IDEA as a remote backend).
        postPatch = "rm -rf plugins/remote-dev-server\n" + old.postPatch;
      });
    in
    {
      environment.systemPackages = [
        idea

        # JDKs — IDEA discovers these via PATH; point Project SDK at
        # /nix/store/…-openjdk-<version>/lib/openjdk inside the IDE.
        pkgs.jdk17
        pkgs.jdk21

        # Build tools
        pkgs.maven
        pkgs.gradle
      ];
    };
}
