# obdium.nix notes

`obdium` (from `packages/obdium/`) is an OBD2 automotive diagnostics app. It requires `webkitgtk_4_0` (based on libsoup2 / Tauri v1 / wry <0.38), which was removed from nixpkgs-unstable around 2025-10-08. The package is built using `nixpkgs-webkitgtk40` (pinned to commit `10924657b0dc`), a flake input specifically added to preserve this dependency.

The module adds siigna to the `dialout` group for access to ELM327 USB-serial adapters on `/dev/ttyUSB*`.
