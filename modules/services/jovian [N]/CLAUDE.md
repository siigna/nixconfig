# jovian.nix notes

Split in two modules. `jovian` (shared) holds Steam, Decky, the `deck` user and the watchdog.
`jovian-steamdeck` (nixdeck only) holds Deck hardware (`jovian.devices.steamdeck`, dock/BIOS
updaters, `jupiter-fan-control` mask) and the GDM flow (`deckGdmSession` pin, `nopasswdlogin`, and the
`steamos-session-select` stub overlay). steammachine uses SDDM autostart plus steamos-manager's own
session switching instead, and links `steamos-session-select` to `holo-session-select`.
The XRGaming plugin workarounds (`su` shim, empty `LD_LIBRARY_PATH`, `ENABLE_VKBASALT`) live in
`breezy.nix`.

On nixdeck, `jovian-stubs` is overridden via `nixpkgs.overlays` to add a `steamos-session-select` that kills `$gamescope_pid` directly (or stops `gamescope-session.target`), dropping `deck` back to GDM. It was written when Jovian's `steamos-manager` lacked the `SessionManagement1` D-Bus interface; steamos-manager 26.4.1 has it (`SwitchToDesktopMode`, used by steammachine), so the stub now only exists for nixdeck's GDM flow.

The stub is injected at the front of PATH inside the Steam bubblewrap via the FHS profile (`steam-run-1.0.0.85-fhsenv-profile`), so system-level PATH overrides have no effect — the overlay is the only way to intercept it.

A `steam-launch-watchdog` user service starts with the gamescope session and terminates it after 90 seconds if `steam-launcher.service` never became active, returning the user to the display manager. It must stay `Type=simple`: as a oneshot, `gamescope-session.target` (ordered after the units it wants) stayed "starting" for those 90 s and steamos-manager's Switch to Desktop failed with `TransactionIsDestructive`.

`jovian.decky-loader.user` is set to `"deck"` (matching SteamOS). The Jovian default `"decky"` is a system user with nologin shell, which breaks the XRGaming plugin's `su -l` calls. The `su` wrapper in `extraPackages` delegates to `runuser` because the real `su` requires a TTY that the decky-loader systemd service lacks.
