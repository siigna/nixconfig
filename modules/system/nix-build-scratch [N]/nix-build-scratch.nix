{ ... }:
{
  flake.modules.nixos.nix-build-scratch =
    { ... }:
    {
      # Run Nix build sandboxes out of a 120G ext4 image hosted on the NTFS
      # partition (nvme0n1p3) instead of on the ext4 root.
      #
      # Why: the root filesystem is ~1T but is almost entirely consumed by the
      # Steam library, while nvme0n1p3 sits mostly idle with hundreds of GB
      # free. Large builds need a lot of scratch — the Valve kernel peaks around
      # 43G — and were failing outright with
      #   fatal error: error writing to /build/ccXXXXXX.s: No space left on device
      #
      # Why an image rather than building on /mnt/win directly: build sandboxes
      # need real POSIX ownership, hardlinks and device nodes, none of which
      # ntfs3 provides. Putting ext4 inside a file gives full POSIX semantics;
      # NTFS only ever sees one opaque 120G file.
      #
      # Scratch only — deliberately NOT the Nix store. If this mount fails, a
      # build fails and is recoverable (recreate with mkfs.ext4); if the store
      # lived here a failed mount would leave the system unbootable. Hence
      # nofail, plus depends so the NTFS parent is mounted first.
      #
      # Recreate the backing image with:
      #   fallocate -l 120G /mnt/win/nixos/nix-build-scratch.img
      #   mkfs.ext4 -m 0 -L nixbuild /mnt/win/nixos/nix-build-scratch.img
      fileSystems."/var/nix-build" = {
        device = "/mnt/win/nixos/nix-build-scratch.img";
        fsType = "ext4";
        options = [
          "loop"
          "nofail"
          "noatime"
        ];
        depends = [ "/mnt/win" ];
      };

      nix.settings.build-dir = "/var/nix-build";
    };
}
