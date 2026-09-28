{ ... }:
{
  flake.modules.nixos.vesc-tool =
    { pkgs, ... }:
    {
      # VESC Tool — IDE for configuring VESC-compatible motor controllers.
      # Packaged upstream as a flake; the overlay is applied in nixos-base.
      #
      # The overlay also exposes tier builds (vesc-tool-free/bronze/silver/
      # gold/platinum) and bldc-fw. We install the plain "original" build.
      environment.systemPackages = [ pkgs.vesc-tool ];

      # VESCs appear as USB CDC-ACM serial devices (/dev/ttyACM*). dialout owns
      # those nodes, so non-root access needs group membership. Already granted
      # for obdium's ELM327 adapters; repeated here so this module stands alone.
      users.users.siigna.extraGroups = [ "dialout" ];
    };
}
