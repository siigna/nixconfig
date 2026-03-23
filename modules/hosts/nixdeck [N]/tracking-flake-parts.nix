{ inputs, ... }:
{
  flake.nixosConfigurations = inputs.self.lib.mkNixosTracked "x86_64-linux" "nixdeck";
}
