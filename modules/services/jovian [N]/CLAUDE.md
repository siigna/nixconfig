# jovian.nix notes

The `jovian-stubs` package is overridden via `nixpkgs.overlays` to replace `steamos-session-select` with a working implementation. The upstream stub calls `steamosctl switch-to-desktop-mode` which hangs because the `SessionManagement1` D-Bus interface is absent in Jovian's `steamos-manager`. The override kills `$gamescope_pid` directly (or stops `gamescope-session.target` as a fallback), which drops the `deck` user back to GDM.

The stub is injected at the front of PATH inside the Steam bubblewrap via the FHS profile (`steam-run-1.0.0.85-fhsenv-profile`), so system-level PATH overrides have no effect — the overlay is the only way to intercept it.

A `steam-launch-watchdog` user service starts with the gamescope session and terminates it after 90 seconds if `steam-launcher.service` never became active, returning the user to GDM.

`jovian.decky-loader.user` is set to `"deck"` (matching SteamOS). The Jovian default `"decky"` is a system user with nologin shell, which breaks the XRGaming plugin's `su -l` calls. The `su` wrapper in `extraPackages` delegates to `runuser` because the real `su` requires a TTY that the decky-loader systemd service lacks.
