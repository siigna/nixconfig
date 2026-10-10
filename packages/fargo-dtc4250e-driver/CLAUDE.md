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
