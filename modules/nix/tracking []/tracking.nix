{ inputs, ... }:
{
  perSystem =
    { system, pkgs, ... }:
    {
      devShells.tracking = pkgs.mkShell {
        packages = [
          # Patched nix evaluator with dependency-tracking builtins
          inputs.nix-tracking.packages.${system}.nix
          # nixos-config TUI — only exists in oddlama's nixpkgs fork
          inputs.nixpkgs-tracking.legacyPackages.${system}.nixos-config
        ];
      };
    };
}
