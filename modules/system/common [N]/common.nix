{ inputs, ... }:
{
  # Settings shared by every interactive host (nixdeck, steammachine): overlays, bootloader,
  # Plymouth, networking, nix daemon. Desktop-only bits (GNOME, printing, GDM monitors) stay in
  # nixos-base. Hosts set networking.hostName and system.stateVersion themselves.
  flake.modules.nixos.nixos-common =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      options.nixdeck.useGrub = lib.mkEnableOption "GRUB bootloader instead of systemd-boot";

      config = {
        nixpkgs.config.allowUnfree = true;
        nixpkgs.overlays = [
          (import inputs.packages)
          inputs.claude-code-nix.overlays.default
          inputs.codex-cli-nix.overlays.default
          inputs.hermes-agent.overlays.default
          # Upstream overlay.nix reads the deprecated `prev.system` alias (eval warning);
          # same overlay, keyed on stdenv.hostPlatform.system instead.
          (
            final: _:
            import "${inputs.vesc-tool}/pkgs" {
              src = inputs.vesc-tool;
              # gcc-arm-embedded-14 from cache.nixos.org segfaults on every binary (patchelf bug,
              # NixOS/patchelf#674): set RPATH before the interpreter, as NixOS/nixpkgs#577329 does.
              # Drop the override once that fix reaches nixos-unstable.
              bldc-fw =
                inputs.vesc-tool.inputs.bldc-fw.packages.${final.stdenv.hostPlatform.system}.bldc-fw.override
                  {
                    gcc-arm-embedded-14 = final.gcc-arm-embedded-14.overrideAttrs {
                      preFixup = ''
                        find $out -type f | while read f; do
                          patchelf "$f" > /dev/null 2>&1 || continue
                          patchelf --set-rpath ${
                            final.lib.makeLibraryPath [
                              "$out"
                              final.stdenv.cc.cc
                              final.ncurses6
                              final.libxcrypt-legacy
                              final.xz
                              final.zstd
                            ]
                          } "$f" || true
                          patchelf --set-interpreter $(cat ${final.stdenv.cc}/nix-support/dynamic-linker) "$f" || true
                        done
                      '';
                    };
                  };
              pkgs = final;
            }
          )
          # patchelf 0.19.2 aborts on semgrep-core's prebuilt binary (tracking:
          # NixOS/nixpkgs#577387). Fix it up with 0.15.2, as upstream does for rgp; drop once
          # nixos-unstable has a fixed patchelf.
          (final: prev: {
            semgrep = final.python3.pkgs.toPythonApplication (
              final.python3.pkgs.semgrep.override {
                semgrep-core = final.python3.pkgs.semgrep.semgrep-core.override {
                  patchelf = prev.patchelf.overrideAttrs (
                    finalAttrs: _: {
                      version = "0.15.2";
                      src = final.fetchurl {
                        url = "https://github.com/NixOS/patchelf/releases/download/${finalAttrs.version}/patchelf-${finalAttrs.version}.tar.bz2";
                        hash = "sha256-F3RfVkFZyOIo/EEtplogSLhGxLa0Igt3y/IkFuAvLXw=";
                      };
                    }
                  );
                };
              }
            );
          })
          # obdium (Tauri v1) requires webkitgtk-4.0 + libsoup-2.4, both removed/insecure
          # in current nixpkgs. Build it from a pinned nixpkgs that still has them.
          (final: _: {
            obdium =
              let
                legacyPkgs = import inputs.nixpkgs-webkitgtk40 {
                  inherit (final.stdenv.hostPlatform) system;
                  config.allowUnfree = true;
                  # webkitgtk_4_0 pulls in libsoup-2.4 (EOL but the only option for
                  # Tauri v1 / wry <0.38 which hardcodes the webkit2gtk-4.0 API).
                  config.permittedInsecurePackages = [ "libsoup-2.74.3" ];
                };
              in
              legacyPkgs.callPackage (inputs.packages + "/obdium") { };
          })
        ];

        boot = {
          initrd.systemd.enable = true;
          kernelParams = [
            "quiet"
            "splash"
            "loglevel=3"
            "rd.udev.log_level=3"
            "systemd.show_status=auto"
            "boot.shell_on_fail"
            "systemd.debug-shell=1"
          ];
          loader = {
            efi.canTouchEfiVariables = true;
            timeout = 2;
            systemd-boot.enable = !config.nixdeck.useGrub;
            systemd-boot.configurationLimit = 3;
            grub = lib.mkIf config.nixdeck.useGrub {
              enable = true;
              device = "nodev";
              efiSupport = true;
            };
          };
          plymouth = {
            enable = true;
            themePackages = [ pkgs.adi1090x-plymouth ];
            theme = "lone";
          };
        };

        networking.networkmanager.enable = true;

        time.timeZone = "America/Los_Angeles";

        nix.gc = {
          automatic = true;
          dates = "03:15";
          options = "-d";
        };

        nix.settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          trusted-users = [
            "root"
            "siigna"
          ];
          auto-optimise-store = true;
        };

        security.sudo.wheelNeedsPassword = false;

        # https://github.com/NixOS/nixpkgs/issues/180175
        systemd.services.NetworkManager-wait-online.enable = false;
      };
    };
}
