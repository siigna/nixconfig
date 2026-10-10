# xreal-one.nix notes

`xreal-one-ctl` (from `packages/xreal-one-ctl/`) is a Rust CLI built from the [0xcaff/xr-tools](https://github.com/0xcaff/xr-tools) workspace. Primary use: `xreal_one_ctl enable-camera` turns on the XReal One Pro's passthrough eye camera, causing the device to reconnect and expose a UVC camera interface.

`ar-compositor` (from `packages/ar-compositor/`) is a Python/GTK3/GStreamer app that composites the glasses camera feed with a Mutter ScreenCast desktop capture, with a live preview window and a Record button. Saves recordings to `~/Videos`.

Both tools need USB access without sudo — the module adds udev rules for vendor ID `0x3318` (XReal) granting `plugdev` group access, and adds siigna to `plugdev`.
