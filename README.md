# nixconfig

My NixOS configuration for two Valve machines:

- **nixdeck**: a Steam Deck running NixOS with [Jovian-NixOS](https://github.com/Jovian-Experiments/Jovian-NixOS).
  It logs into gaming mode from GDM, runs GNOME as the desktop, and carries my XR glasses setup
  and dev tools.
- **steammachine**: a Steam Machine (`fremont`) on the TV. It boots straight into gaming mode,
  switches to Plasma for desktop mode, and is also the Deck's remote Nix builder.

This is a personal config. I've published it in case parts of it help someone, but it isn't
meant to be imported as-is.

## Layout

The flake uses the [dendritic pattern](https://github.com/mightyiam/dendritic).
[flake-parts](https://flake.parts) and [import-tree](https://github.com/denful/import-tree) load
every `.nix` file under `modules/`, and each file registers a named NixOS module
(`flake.modules.nixos.<name>`). A host is a list of those names:

```text
modules/
  hosts/        nixdeck, steammachine (configuration + hardware)
  system/       shared base: boot, Plymouth, networking, nix settings
  services/     Jovian, Tailscale, remote builders, Steam library, …
  programs/     packages, XR drivers, light bar daemon, TV apps, …
  users/
  nix/          flake-parts plumbing: the mkNixos helper and module registry
packages/       nixpkgs overlay with custom packages
```

Directory names end in `[N]` (NixOS only) or `[]` (any platform), for example
`modules/programs/lightbar [N]/`. That's a naming convention, not Nix syntax.

Most module directories have a `CLAUDE.md` with design notes and gotchas. I wrote them for an AI
coding assistant, but they're the most detailed documentation in the repo.

## Things that might be interesting

- **Steam Machine on Jovian.** The host uses the unmerged device module from
  [Jovian-NixOS#598](https://github.com/Jovian-Experiments/Jovian-NixOS/pull/598) through its own
  flake input, so the Deck stays on Jovian master. A kernel patch enables HDMI-CEC through the
  board's ChromeOS EC, so the TV remote drives Steam. Suspend is disabled because the box is also
  a build server. Details in `modules/hosts/steammachine [N]/CLAUDE.md`.
- **Light bar daemon** (`modules/programs/lightbar [N]/`). It turns the Steam Machine's 17-LED
  strip into a CPU, GPU and network meter, with the CPU and GPU bars pulsing when RAM or VRAM run
  high. A second mode breathes while Nix builds run.
- **Remote builds.** `make build` evaluates on the Deck, builds on the Steam Machine
  (`--build-host`), and copies back only the finished system, so a big nixpkgs bump doesn't
  swamp the Deck.
- **XR on the Deck.** A patched Breezy Desktop driver, plus XReal One support
  (`modules/programs/breezy [N]/`, `modules/programs/xreal-one [N]/`, `packages/ar-compositor/`).
- **Custom packages** in `packages/`: a Plymouth theme, Breezy, an OBD2 diagnostics app, a CUPS
  driver for a Fargo card printer, and Claude Code add-ons (a cost statusline, a hook that
  auto-approves read-only shell commands, a pinned plugin marketplace).

## Requirements

x86_64 Linux, Nix with flakes enabled, and nixos-unstable (pinned in `flake.lock`). Most modules
assume the hardware above: a Steam Deck, a Steam Machine, or both.

## Borrowing a module

Every module is exported as `modules.nixos.<name>`, so another flake can import one without the
rest of this config. The light bar daemon, for example:

```nix
{
  inputs.nixconfig.url = "github:siigna/nixconfig";
  inputs.nixpkgs.follows = "nixconfig/nixpkgs";

  outputs = { nixpkgs, nixconfig, ... }: {
    nixosConfigurations.my-steam-machine = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixconfig.modules.nixos.lightbar
        { steammachine.lightbar.enable = true; }
        ./configuration.nix
      ];
    };
  };
}
```

After a switch, `systemctl status lightbar` shows the daemon running, and `sudo lightbar mode build`
switches the strip to build mode until the next reboot. Run `nix eval .#modules.nixos --apply
builtins.attrNames` in this repo to list the module names. Many of them depend on each other or on
Jovian, so check a module's imports before borrowing it.

## Usage

These targets are for working on this config itself:

```bash
make build                                              # build nixdeck → ./result
make switch                                             # build and activate
make switch HOST=steammachine TARGET=root@steammachine  # deploy the Steam Machine over SSH
make update                                             # nix flake update
```

The Fargo printer driver and its extras aren't redistributable, so they're `requireFile`s: add
them to the store by hand, and evaluation prints the instructions if they're missing.

## License

MIT, see [LICENSE](LICENSE). That covers this configuration. Vendored patches keep their own
licences; for example, the CEC kernel patch is GPL-2.0, like the kernel it patches.
