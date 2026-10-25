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

    # Steam Deck / Jovian-NixOS — tracks master; flake.lock pins it and `make update` moves it
    jovian-nixos = {
      flake = false;
      url = "github:Jovian-Experiments/Jovian-NixOS";
    };

    # steammachine only: Jovian PR #598 (K900's jovian.devices.steammachine), as GitHub's
    # test-merge onto current master so it doesn't lag the master pin above. Drop this input
    # and go back to `jovian` once #598 lands.
    jovian-nixos-fremont = {
      flake = false;
      url = "git+https://github.com/Jovian-Experiments/Jovian-NixOS?ref=refs/pull/598/merge&shallow=1";
    };

    # Custom overlay packages (adi1090x-plymouth, etc.)
    packages = {
      flake = false;
      url = "path:./packages";
    };

    # Pinned nixpkgs for packages requiring webkitgtk-4.0 (removed in unstable ~2025-10-08).
    # Last commit with a real webkitgtk_4_0 (libsoup2-based, Tauri v1 / wry <0.38).
    nixpkgs-webkitgtk40.url = "github:nixos/nixpkgs/10924657b0dc";

    # Always-up-to-date Claude Code (updated hourly, ahead of nixpkgs)
    claude-code-nix.url = "github:sadjow/claude-code-nix";

    # Always-up-to-date Codex CLI
    codex-cli-nix.url = "github:sadjow/codex-cli-nix";

    # Hermes Agent (Nous Research) — packaged upstream as a uv2nix flake
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.home-manager.follows = "home-manager";
    };

    # Prebuilt nix-index database (weekly) + comma + command-not-found hook
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # VESC Tool — motor controller IDE, packaged upstream as a flake
    vesc-tool = {
      url = "github:vedderb/vesc_tool";
      inputs.nixpkgs.follows = "nixpkgs";
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
