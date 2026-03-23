{ ... }:
{
  flake.modules.nixos.hosts-file = {
    networking.extraHosts = ''
      172.31.5.17 proxmox
      172.31.5.21 nixmox
      172.31.5.28 octopi
    '';
  };
}
