{
  inputs,
  lib,
  ...
}:
{
  # Enable the flake.modules.{nixos,darwin,homeManager,generic} options
  imports = [ inputs.flake-parts.flakeModules.modules ];

  # Helper functions for creating system configurations
  options.flake.lib = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
  };

  config = {
    # Only build for x86_64-linux (no perSystem modules needed, but flake-parts requires this)
    systems = [ "x86_64-linux" ];

    flake.lib = {
      mkNixos = system: name: {
        ${name} = inputs.nixpkgs.lib.nixosSystem {
          modules = [
            inputs.self.modules.nixos.${name}
            { nixpkgs.hostPlatform = lib.mkDefault system; }
          ];
        };
      };

      mkNixosTracked = system: name:
        let
          # Patch our own nixpkgs (same commit as the regular build) with the
          # tracking infrastructure, so tracked builds share package store paths
          nixpkgsPatched = inputs.nixpkgs.legacyPackages.${system}.applyPatches {
            name = "nixpkgs-patched-tracking";
            src = inputs.nixpkgs;
            patches = [ "${inputs.nixos-config-tui}/contrib/nixpkgs-add-tracking.diff" ];
          };
          # nixosSystem isn't in nixpkgs/lib — nixpkgs' flake.nix assembles it
          # by importing eval-config.nix with an extended lib. Replicate that here
          # using the patched source so trackDependencies is supported.
          patchedLib = import "${nixpkgsPatched}/lib";
          nixosSystem = args: import "${nixpkgsPatched}/nixos/lib/eval-config.nix" ({
            lib = patchedLib;
            system = null;
            modules = args.modules or [ ];
          } // builtins.removeAttrs args [ "modules" ]);
        in
        {
          "${name}-tracked" = nixosSystem {
            trackDependencies = true;
            modules = [
              inputs.self.modules.nixos.${name}
              { nixpkgs.hostPlatform = lib.mkDefault system; }
            ];
          };
        };
    };
  };
}
