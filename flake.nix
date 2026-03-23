{
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Steam Deck / Jovian-NixOS — pinned to same commit as original config
    jovian-nixos = {
      flake = false;
      url = "github:Jovian-Experiments/Jovian-NixOS/425b357";
    };

    # Custom overlay packages (adi1090x-plymouth, etc.)
    packages = {
      flake = false;
      url = "path:./packages";
    };

    # Patched nix evaluator with dependency-tracking builtins (for devShell)
    nix-tracking.url = "github:oddlama/nix/thunk-origins-v1";

    # Patched nixpkgs — only used to get the nixos-config TUI binary in devShell
    nixpkgs-tracking.url = "github:oddlama/nixpkgs/thunk-origins-v1";

    # nixos-config-tui patches — applied to our own nixpkgs in mkNixosTracked
    # so the tracked build shares package store paths with our regular build
    nixos-config-tui = {
      flake = false;
      url = "github:oddlama/nixos-config-tui";
    };

  };
}
