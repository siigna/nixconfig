{ ... }:
{
  flake.modules.nixos.nixbuild = {
    programs.ssh.extraConfig = ''
      Host eu.nixbuild.net
        PubkeyAcceptedKeyTypes ssh-ed25519
        IdentityFile /root/.ssh/my-nixbuild-key

      Host nixbuilder
        PubkeyAcceptedKeyTypes ssh-ed25519
        IdentityFile /root/.ssh/nixbuilder-key
        StrictHostKeyChecking accept-new
    '';

    programs.ssh.knownHosts = {
      nixbuild = {
        hostNames = [ "eu.nixbuild.net" ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM";
      };
    };

    nix = {
      distributedBuilds = true;
      buildMachines = [
        # Local Proxmox VM — preferred (speedFactor = 4) when available.
        # Falls back to nixbuild.net for overflow or when unreachable.
        # SSH key: sudo ssh-keygen -t ed25519 -f /root/.ssh/nixbuilder-key -N ""
        # Then add the pubkey to nixbuilder.authorizedKeys in:
        #   modules/hosts/nixbuilder [N]/configuration.nix
        {
          hostName = "nixbuilder";
          system = "x86_64-linux";
          sshUser = "nix-ssh";
          maxJobs = 4;
          supportedFeatures = [ "nix-command" "big-parallel" ];
          speedFactor = 4;
        }
        {
          hostName = "eu.nixbuild.net";
          system = "x86_64-linux";
          maxJobs = 100;
          supportedFeatures = [ "benchmark" "big-parallel" ];
          speedFactor = 1;
        }
        {
          hostName = "eu.nixbuild.net";
          system = "i686-linux";
          maxJobs = 100;
          supportedFeatures = [ "benchmark" "big-parallel" ];
          speedFactor = 1;
        }
      ];
      extraOptions = ''
        builders-use-substitutes = true
      '';
    };
  };
}
