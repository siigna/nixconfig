FLAKE ?= 1

ifeq ($(FLAKE),1)
FLAKE_ARG = --flake .#nixdeck
else
FLAKE_ARG =
endif

build:
	nixos-rebuild build $(FLAKE_ARG)

switch:
	sudo nixos-rebuild switch $(FLAKE_ARG)

boot:
	sudo nixos-rebuild boot $(FLAKE_ARG)

update:
	nix flake update

# Build a qcow2 image for the nixbuilder Proxmox VM.
# Import into Proxmox with qm importdisk after creation.
image-nixbuilder:
	nixos-rebuild build-image --flake .#nixbuilder --image-variant proxmox

# Option dependency tracking (requires patched nix — provided via devShell)
# Run track-build first to populate ./result, then use the diff/show targets.

track-build:
	nix develop .#tracking --command nixos-rebuild build --flake .#nixdeck-tracked

# Browse from flake reference directly (no prior track-build needed)
track-show:
	nix develop .#tracking --command nixos-config show .#nixdeck-tracked

# Browse ./result from a prior track-build
track-show-result:
	nix develop .#tracking --command nixos-config show ./result

# Diff current system vs ./result (all values)
track-diff:
	nix develop .#tracking --command nixos-config diff /run/current-system ./result

# Diff showing only explicitly defined values
track-diff-explicit:
	nix develop .#tracking --command nixos-config diff --explicit /run/current-system ./result

# Textual pseudo-nix diff of explicitly defined values
track-text-diff:
	nix develop .#tracking --command nixos-config text-diff --explicit /run/current-system ./result

.PHONY: build switch boot update image-nixbuilder \
        track-build track-show track-show-result \
        track-diff track-diff-explicit track-text-diff
