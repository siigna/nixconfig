{ ... }:
{
  # Steam Machine light bar (17 RGB LEDs, Valve's leds-valve driver; see the steammachine host
  # notes for the sysfs interface). One root daemon drives the configured mode; `sudo lightbar
  # mode <mode>` overrides it until reboot (/run/lightbar/mode), `sudo lightbar reset` drops that.
  flake.modules.nixos.lightbar =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.steammachine.lightbar;
      inherit (lib) mkOption types;

      rgb = mkOption {
        type = types.listOf (types.ints.between 0 255);
        description = "Colour as [ R G B ].";
      };
      look = {
        effect = mkOption {
          type = types.enum [
            "patrol"
            "breath"
            "factory"
            "normal"
            "off"
            "rainbow"
            "demo"
            "manual"
          ];
          default = "breath";
          description = "Firmware effect for the whole strip.";
        };
        color = rgb // {
          default = [
            1
            90
            255
          ];
        };
        brightness = mkOption {
          type = types.ints.between 0 255;
          default = 56;
          description = "Strip brightness (brightness_scale); the BIOS default is 56.";
        };
        delay = mkOption {
          type = types.ints.between 0 20;
          default = 8;
          description = "Effect speed (delay register); 8 is the shipped value.";
        };
      };

      settings = pkgs.writeText "lightbar.json" (
        builtins.toJSON {
          inherit (cfg) mode fixed;
          build = {
            inherit (cfg.build) color;
          };
          meter = cfg.meter;
          # What the strip looked like as shipped; put back whenever the daemon stops.
          restore = {
            effect = "breath";
            color = [
              1
              90
              255
            ];
            brightness = 56;
            delay = 8;
          };
        }
      );

      daemon = pkgs.writers.writePython3 "lightbar-daemon" {
        flakeIgnore = [ "E501" ];
      } (builtins.readFile ./lightbar.py);

      cli = pkgs.writeShellApplication {
        name = "lightbar";
        runtimeInputs = [
          pkgs.coreutils
          config.systemd.package
        ];
        text = ''
          override=/run/lightbar/mode
          case "''${1:-}" in
            mode)
              if [ -z "''${2:-}" ]; then
                if [ -e "$override" ]; then echo "$(cat "$override") (runtime override)"; else echo "${cfg.mode} (configured)"; fi
                exit 0
              fi
              case "$2" in meter|build|fixed|off) ;; *) echo "modes: meter build fixed off" >&2; exit 2 ;; esac
              mkdir -p /run/lightbar
              echo "$2" > "$override"
              echo "lightbar: $2 (until reboot or 'lightbar reset')"
              ;;
            reset)
              rm -f "$override"
              echo "lightbar: back to configured mode ${cfg.mode}"
              ;;
            restart)
              systemctl restart lightbar.service
              ;;
            *)
              echo "usage: lightbar mode [meter|build|fixed|off] | reset | restart" >&2
              exit 2
              ;;
          esac
        '';
      };
    in
    {
      options.steammachine.lightbar = {
        enable = lib.mkEnableOption "the Steam Machine light bar daemon";

        mode = mkOption {
          type = types.enum [
            "meter"
            "build"
            "fixed"
            "off"
          ];
          default = "meter";
          description = ''
            meter: CPU, GPU and network bar graphs. build: breathe build.color while Nix builds run,
            fixed look otherwise. fixed: the fixed.* look. off: strip dark.
          '';
        };

        fixed = look;

        build.color = rgb // {
          default = [
            255
            120
            0
          ];
          description = "Breathing colour while any nixbld process is running.";
        };

        meter = {
          cpuLeds = mkOption {
            type = types.listOf (types.ints.between 0 16);
            default = lib.range 0 5;
            description = "LED indices of the CPU bar, bottom of the bar first.";
          };
          gpuLeds = mkOption {
            type = types.listOf (types.ints.between 0 16);
            default = lib.range 6 11;
            description = "LED indices of the GPU bar (amdgpu gpu_busy_percent), bottom first; [ ] hides it.";
          };
          gpuColor = rgb // {
            default = [
              190
              0
              255
            ];
          };
          netLeds = mkOption {
            type = types.listOf (types.ints.between 0 16);
            default = lib.range 12 16;
            description = "LED indices of the network bar, bottom of the bar first.";
          };
          netInterface = mkOption {
            type = types.str;
            default = "wlp6s0";
            description = "Interface whose rx+tx rate the network bar shows.";
          };
          netMaxBytesPerSec = mkOption {
            type = types.ints.positive;
            default = 12500000;
            description = "Rate that fills the network bar (log scale from 10 KB/s); 100 Mbit/s.";
          };
          netColor = rgb // {
            default = [
              0
              200
              255
            ];
          };
          brightness = mkOption {
            type = types.ints.between 0 255;
            default = 56;
            description = "Strip brightness (brightness_scale) while metering.";
          };
          intervalMs = mkOption {
            type = types.ints.between 50 5000;
            default = 250;
            description = "Update interval.";
          };
          smoothing = mkOption {
            type = types.numbers.between 0.05 1.0;
            default = 0.4;
            description = "Exponential smoothing factor per update (1 = none).";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cli ];

        systemd.services.lightbar = {
          description = "Steam Machine light bar (${cfg.mode})";
          wantedBy = [ "multi-user.target" ];
          after = [ "systemd-modules-load.service" ];
          restartTriggers = [ settings ];
          serviceConfig = {
            ExecStart = "${daemon} ${settings}";
            Restart = "on-failure";
            RestartSec = 5;
            Nice = 10;
          };
        };
      };
    };
}
