{ pkgs ? (
    let
      sources = import ./nix/sources.nix;
    in
    import sources.nixpkgs {
      overlays = [
        (import "${sources.gomod2nix}/overlay.nix")
      ];
    }
  )
}:

pkgs.buildGoApplication {
  pname = "llama";
  version = "5316804";
  pwd = ./.;
  src = ./.;
  modules = ./gomod2nix.toml;
}
