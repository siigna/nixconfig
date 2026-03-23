{ ... }:
{
  flake.modules.nixos.tailscale =
    { config, pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.tailscale ];

      services.tailscale.enable = true;
      networking.firewall.checkReversePath = "loose";
      networking.firewall = {
        trustedInterfaces = [ "tailscale0" ];
        allowedUDPPorts = [ config.services.tailscale.port ];
      };
    };
}
