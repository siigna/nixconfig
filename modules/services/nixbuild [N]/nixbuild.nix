{ ... }:
{
  flake.modules.nixos.nixbuild = {
    programs.ssh.extraConfig = ''
      Host eu.nixbuild.net
        PubkeyAcceptedKeyTypes ssh-ed25519
        IdentityFile /root/.ssh/my-nixbuild-key

      Host steammachine
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
        # Steam Machine over Tailscale — preferred (speedFactor = 4) when reachable; its daemon
        # runs at idle priority so builds yield to games. Falls back to nixbuild.net for
        # overflow or while it is asleep/off.
        # SSH key: /root/.ssh/nixbuilder-key (name predates the Steam Machine); its pubkey is in
        # builder.authorizedKeys in modules/hosts/steammachine [N]/configuration.nix.
        {
          hostName = "steammachine";
          system = "x86_64-linux";
          sshUser = "nix-ssh";
          maxJobs = 2;
          supportedFeatures = [
            "nix-command"
            "big-parallel"
          ];
          speedFactor = 4;
        }
        {
          hostName = "eu.nixbuild.net";
          system = "x86_64-linux";
          maxJobs = 100;
          supportedFeatures = [
            "benchmark"
            "big-parallel"
          ];
          speedFactor = 1;
        }
        {
          hostName = "eu.nixbuild.net";
          system = "i686-linux";
          maxJobs = 100;
          supportedFeatures = [
            "benchmark"
            "big-parallel"
          ];
          speedFactor = 1;
        }
      ];
      extraOptions = ''
        builders-use-substitutes = true
      '';
    };
  };
}
