FLAKE ?= 1
NOBUILDERS ?= 0
HOST ?= nixdeck
# Deploy over SSH instead of locally, e.g. make switch HOST=steammachine TARGET=root@steammachine
TARGET ?=

ifeq ($(FLAKE),1)
FLAKE_ARG = --flake .\#$(HOST)
else
FLAKE_ARG =
endif

ifneq ($(TARGET),)
TARGET_ARG = --target-host $(TARGET)
else
TARGET_ARG =
endif

ifeq ($(NOBUILDERS),1)
BUILDERS_ARG = --builders ''
else
BUILDERS_ARG =
endif

build:
	nixos-rebuild build $(FLAKE_ARG) $(BUILDERS_ARG)

switch:
	sudo nixos-rebuild switch $(FLAKE_ARG) $(BUILDERS_ARG) $(TARGET_ARG)

boot:
	sudo nixos-rebuild boot $(FLAKE_ARG) $(BUILDERS_ARG) $(TARGET_ARG)

update:
	nix flake update

update-claude:
	nix flake update claude-code-nix

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

.PHONY: build switch boot update update-claude image-nixbuilder \
        track-build track-show track-show-result \
        track-diff track-diff-explicit track-text-diff
