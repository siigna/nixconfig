# fargo-dtc4250e-driver src

HID gates the driver download behind a form and the tarball is not redistributable, so `src` is a
`requireFile`. On a machine that has never built it, evaluation fails with instructions. Satisfy it
once:

```bash
# download "SFW-02132 Rev B - DTC4250e Linux Printer Driver v1.0.0.4" from
# https://www.hidglobal.com/drivers, unpack the outer archive, then:
nix-store --add-fixed sha256 DTC4250e-1.0.0.4-x64.tar.gz
```

This replaced an absolute `/home/siigna/Downloads/...` path, which was the sole reason every
`nixos-rebuild` target used to need `--impure`.

The added path has no GC root, so the nightly `nix-gc` deletes it after the driver is built; the
next nixpkgs bump then fails on the `requireFile` again. Root it after adding:

```bash
nix-store --realise /nix/store/…-DTC4250e-1.0.0.4-x64.tar.gz \
  --add-root ~/.local/state/nix-roots/fargo-dtc4250e-src --indirect
```

`make build` realises on steammachine (`BUILDHOST`), and `--build-host` copies only derivations,
so the build host needs its own copy: `nix copy --to ssh-ng://nix-ssh@steammachine /nix/store/…`.
