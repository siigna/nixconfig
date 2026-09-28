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
    ];
    nixdeck.useGrub = false;
  };
}
