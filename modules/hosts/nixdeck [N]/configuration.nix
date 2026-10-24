{ inputs, ... }:
{
  flake.modules.nixos.nixdeck = {
    imports = with inputs.self.modules.nixos; [
      nixos-base
      hardware-nixdeck
      hosts-file
      fonts
      gdm-nopasswdlogin
      jovian
      jovian-steamdeck
      system-packages
      tailscale
      nixbuild
      nix-build-scratch
      bootnext
      siigna
      boucheblaster
      steam-library
      radio
      breezy
      intellij
      xreal-one
      obdium
      vesc-tool
      claude-code
      nix-index
    ];
    nixdeck.useGrub = false;
    networking.hostName = "nixdeck";
    # Substitution, unpacking and the preferLocalBuild derivations of a rebuild still run here;
    # keep them from starving the desktop or a game.
    nix.daemonCPUSchedPolicy = "idle";
    nix.daemonIOSchedClass = "idle";
    system.stateVersion = "22.11";
  };
}
