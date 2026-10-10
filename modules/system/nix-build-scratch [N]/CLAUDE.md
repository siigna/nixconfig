# nix-build-scratch.nix notes

`/var/nix-build` is an ext4 image on `/mnt/win` (nvme0n1p3), because root is full of the Steam library
while large builds (Valve kernel peaks ~43G) need scratch. An image rather than ntfs3 directly: build
sandboxes need real ownership, hardlinks and device nodes. Scratch only, never the store — mounted
`nofail` so a mount failure breaks a build, not boot. Recreate with `fallocate` + `mkfs.ext4` (exact
commands in the module comment).
