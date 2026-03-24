{ ... }:
{
  flake.modules.nixos.breezy =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = [
        pkgs.breezy-desktop
        (pkgs.writeShellApplication {
          name = "breezy-diag";
          runtimeInputs = with pkgs; [
            xxd
            systemd
            coreutils
          ];
          text = ''
            echo "=== XR Driver State ==="
            cat /dev/shm/xr_driver_state 2>/dev/null || echo "(no state file)"

            echo ""
            echo "=== Driver Service Status ==="
            systemctl --user status xr-driver --no-pager 2>/dev/null | head -10

            echo ""
            echo "=== Seat Watcher Status ==="
            systemctl --user status xr-driver-seat-watcher --no-pager 2>/dev/null | head -6

            echo ""
            echo "=== IMU File ==="
            if [ -f /dev/shm/breezy_desktop_imu ]; then
                stat /dev/shm/breezy_desktop_imu
                echo "First 32 bytes (hex):"
                xxd /dev/shm/breezy_desktop_imu | head -2
                echo "(byte 0 = version, byte 1 = enabled flag [1=enabled 0=disabled])"
            else
                echo "(no IMU file)"
            fi

            echo ""
            echo "=== Control File ==="
            cat /dev/shm/xr_driver_control 2>/dev/null || echo "(no control file)"

            echo ""
            echo "=== Extension Log (last 20 lines) ==="
            latest=$(find ~/.local/state/breezy_gnome/logs/gjs/ -name "*.log" -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)
            if [ -n "''${latest:-}" ]; then
                tail -20 "$latest"
            else
                echo "(no extension log)"
            fi

            echo ""
            echo "=== Driver Journal (last 10 lines) ==="
            journalctl --user -u xr-driver -n 10 --no-pager 2>/dev/null

            echo ""
            echo "=== xr_driver_cli path ==="
            stat ~/.local/bin/xr_driver_cli 2>/dev/null || echo "(not found)"
            stat /run/current-system/sw/bin/xr_driver_cli 2>/dev/null || echo "(not in sw/bin)"
          '';
        })
      ];

      # Install vkBasalt Vulkan implicit layer JSON system-wide. Steam
      # recreates ~/.local/share/vulkan/implicit_layer.d/ at login, so
      # user-level layer files get wiped. /etc/vulkan/ is root-owned
      # and the Vulkan loader checks it alongside user dirs.
      # The library_path points to deck's home (FHS binary, only works
      # inside Steam's FHS sandbox).
      environment.etc."vulkan/implicit_layer.d/vkBasalt.json".text = builtins.toJSON {
        file_format_version = "1.0.0";
        layer = {
          name = "VK_LAYER_VKBASALT_post_processing";
          type = "GLOBAL";
          library_path = "/home/deck/.local/lib/libvkbasalt.so";
          api_version = "1.3.223";
          implementation_version = "1";
          description = "a post processing layer";
          functions = {
            vkGetInstanceProcAddr = "vkBasalt_GetInstanceProcAddr";
            vkGetDeviceProcAddr = "vkBasalt_GetDeviceProcAddr";
          };
          enable_environment.ENABLE_VKBASALT = "1";
          disable_environment.DISABLE_VKBASALT = "1";
        };
      };
      environment.etc."vulkan/implicit_layer.d/vkBasalt.x86.json".text = builtins.toJSON {
        file_format_version = "1.0.0";
        layer = {
          name = "VK_LAYER_VKBASALT_post_processing";
          type = "GLOBAL";
          library_path = "/home/deck/.local/lib32/libvkbasalt.so";
          api_version = "1.3.223";
          implementation_version = "1";
          description = "a post processing layer";
          functions = {
            vkGetInstanceProcAddr = "vkBasalt_GetInstanceProcAddr";
            vkGetDeviceProcAddr = "vkBasalt_GetDeviceProcAddr";
          };
          enable_environment.ENABLE_VKBASALT = "1";
          disable_environment.DISABLE_VKBASALT = "1";
        };
      };

      # Install XR device udev rules
      services.udev.packages = [ pkgs.breezy-desktop ];

      # Make xr-driver.service available as a systemd user unit.
      # Auto-start on login for all users, including deck — the Decky
      # XRGaming plugin checks is_driver_running() at load time and
      # falls through to an install script that can't work on NixOS
      # (the downloaded binary needs FHS paths). By keeping the driver
      # running, the plugin detects breezy as already installed.
      #
      # Bound to graphical-session.target (active for both GNOME and gamescope)
      # so xr-driver stops on logout. xr-driver-seat-watcher handles user switch
      # (session Active flips false/true without the target stopping).
      systemd.packages = [ pkgs.breezy-desktop ];
      systemd.user.services.xr-driver.wantedBy = [ "graphical-session.target" ];
      systemd.user.services.xr-driver.unitConfig.PartOf = "graphical-session.target";

      # Watch logind session Active property. When the user switches away,
      # Active→false: stop xr-driver (releases USB device for the other user).
      # When switched back, Active→true: start xr-driver fresh (runs ExecStartPre
      # cleanup, then grabs the device again).
      systemd.user.services.xr-driver-seat-watcher = {
        description = "Stop/start xr-driver on session active/inactive transitions";
        wantedBy = [ "graphical-session.target" ];
        after = [ "xr-driver.service" ];
        unitConfig.PartOf = "graphical-session.target";
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "5s";
          ExecStart = pkgs.writeShellScript "xr-driver-seat-watcher" ''
            set -euo pipefail
            uid=$(${pkgs.coreutils}/bin/id -u)

            # Find the seated (user-class) logind session for this user.
            # This is the session whose Active property flips on user switch.
            # Retried via Restart=always if not yet established at service start.
            SESSION_ID=$(${pkgs.systemd}/bin/loginctl list-sessions --no-legend | \
              ${pkgs.gawk}/bin/awk -v uid="$uid" \
                '$2==uid && $6=="user" && $4!="-" {print $1; exit}')
            if [ -z "$SESSION_ID" ]; then
              echo "xr-driver-seat-watcher: no seated session for uid $uid, will retry" >&2
              exit 1
            fi

            SESSION_PATH=$(${pkgs.glib}/bin/gdbus call --system \
              --dest org.freedesktop.login1 \
              --object-path /org/freedesktop/login1 \
              --method org.freedesktop.login1.Manager.GetSession \
              "$SESSION_ID" | \
              ${pkgs.gawk}/bin/awk -F"'" '{for(i=1;i<=NF;i++) if($i~/^\//) {print $i; exit}}')
            echo "xr-driver-seat-watcher: monitoring session $SESSION_ID at $SESSION_PATH"

            ${pkgs.glib}/bin/gdbus monitor --system \
              --dest org.freedesktop.login1 \
              --object-path "$SESSION_PATH" 2>&1 | \
            while IFS= read -r line; do
              if echo "$line" | ${pkgs.gnugrep}/bin/grep -q "'Active':.*<true>"; then
                echo "xr-driver-seat-watcher: session active, starting xr-driver"
                ${pkgs.systemd}/bin/systemctl --user start xr-driver.service 2>/dev/null || true
              elif echo "$line" | ${pkgs.gnugrep}/bin/grep -q "'Active':.*<false>"; then
                echo "xr-driver-seat-watcher: session inactive, stopping xr-driver"
                ${pkgs.systemd}/bin/systemctl --user stop xr-driver.service 2>/dev/null || true
              fi
            done

            echo "xr-driver-seat-watcher: gdbus monitor exited unexpectedly" >&2
            exit 1
          '';
        };
      };

      # xrDriver opens /tmp/shader_runtime_* and /dev/shm/xr_* with O_CREAT.
      # Under fs.protected_regular=1, this fails if another user owns the
      # file in a sticky-bit directory. A user service can't rm files owned
      # by other users, so we:
      #  1. Clean at boot via tmpfiles (covers reboot)
      #  2. Clean before xr-driver starts via a setuid helper (covers user switch)
      systemd.tmpfiles.rules = [
        "r! /tmp/shader_runtime_*"
        "r! /dev/shm/xr_driver_control"
        "r! /dev/shm/xr_driver_state"
        "r! /dev/shm/breezy_desktop_imu"
      ];

      # Clean IPC files that block cross-user xr-driver starts. The xrDriver
      # binary opens /tmp/shader_runtime_* and /dev/shm/xr_* with O_CREAT,
      # which fails under fs.protected_regular=1 if another user owns the
      # file. A user service can't rm other users' files, so we use a
      # system-level template service invoked by a user-level ExecStartPre
      # via sudo. The sudo rule is scoped to just this one script.
      security.sudo.extraRules = [
        {
          groups = [ "users" ];
          commands = [
            {
              command = "/run/current-system/sw/bin/systemctl start xr-driver-cleanup@*";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];

      systemd.services."xr-driver-cleanup@" = {
        description = "Clean stale xr-driver IPC files for %i";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "xr-cleanup" ''
            # Remove stale System V shared memory segments left by xr-driver.
            # The driver creates segments with perms 0666 via shmget(..., 0666|IPC_CREAT).
            # When the /tmp key files are deleted, ftok returns different keys and
            # the old segments become unreachable, causing shmat errors on the next start.
            # Only remove unattached (nattch=0) segments with perms 666 to avoid
            # touching other programs' shared memory.
            ${pkgs.util-linux}/bin/ipcs -m | ${pkgs.gawk}/bin/awk '$4 == 666 && $6 == 0 {print $2}' | while read shmid; do
              ${pkgs.util-linux}/bin/ipcrm -m "$shmid" 2>/dev/null || true
            done

            # Remove the ftok key files and /dev/shm IPC files
            rm -f /tmp/shader_runtime_* /dev/shm/xr_driver_control \
                  /dev/shm/xr_driver_state /dev/shm/breezy_desktop_imu
          '';
        };
      };

      systemd.user.services.xr-driver.serviceConfig.ExecStartPre =
        "-${pkgs.bash}/bin/bash -c '/run/wrappers/bin/sudo /run/current-system/sw/bin/systemctl start xr-driver-cleanup@$(id -un)'";

      # The GNOME Shell extension looks for xr_driver_cli at ~/.local/bin/xr_driver_cli
      # (XDG_BIN_HOME) then /usr/bin/xr_driver_cli. Neither exists on NixOS; the binary
      # is at /run/current-system/sw/bin/xr_driver_cli. Symlink it so the extension's
      # keyboard toggle shortcut (_toggle_xr_effect) can find and invoke the CLI.
      system.activationScripts.breezyGnomeSetup = ''
        siigna_bin="${"/home/siigna/.local/bin"}"
        mkdir -p "$siigna_bin"
        ln -sf /run/current-system/sw/bin/xr_driver_cli "$siigna_bin/xr_driver_cli"
        chown -h siigna:users "$siigna_bin/xr_driver_cli" 2>/dev/null || true
      '';

      # The XRGaming Decky plugin verifies its install by checking:
      #   1. xr-driver is running (handled above)
      #   2. installed_from_plugin_version matches in settings
      #   3. manifest sha256 matches in settings
      #   4. breezy_vulkan_verify succeeds
      #
      # Since we install breezy-desktop via Nix (the tarball binary
      # won't run on NixOS without nix-ld), we shim these checks so
      # the plugin accepts the system-managed driver.
      system.activationScripts.breezyDeckyShim =
        let
          pluginDir = "/var/lib/decky-loader/plugins/decky-XRGaming";
          settingsDir = "/var/lib/decky-loader/settings/decky-XRGaming";
          deckHome = "/home/deck";
        in
        ''
                  # Only run if the XRGaming plugin is installed
                  if [ -d "${pluginDir}" ]; then
                    # Read the plugin version from package.json
                    plugin_version=$(${lib.getExe pkgs.jq} -r '.version' "${pluginDir}/package.json" 2>/dev/null || echo "")
                    if [ -z "$plugin_version" ]; then
                      echo "breezyDeckyShim: could not read plugin version, skipping"
                    else
                      tarball="${pluginDir}/bin/breezyVulkan-x86_64.steamos.tar.gz"

                      # Extract the manifest from the bundled tarball
                      manifest_dir="${deckHome}/.local/share/breezy_vulkan"
                      mkdir -p "$manifest_dir"
                      ${pkgs.gnutar}/bin/tar xzf "$tarball" -C "$manifest_dir" --strip-components=1 breezy_vulkan/manifest 2>/dev/null || true

                      # Set up vkBasalt Vulkan layer for gamescope (Steam/gaming mode).
                      # Libs, config, and shaders go in deck's home. The Vulkan layer
                      # JSON is installed system-wide (see environment.etc below)
                      # because Steam recreates ~/.local/share/vulkan/implicit_layer.d/
                      # at login, wiping any user-placed files.
                      tmp_extract=$(mktemp -d)
                      ${pkgs.gnutar}/bin/tar xzf "$tarball" -C "$tmp_extract" 2>/dev/null || true
                      bv="$tmp_extract/breezy_vulkan"
                      if [ -d "$bv" ]; then
                        lib_dir="${deckHome}/.local/lib"
                        lib32_dir="${deckHome}/.local/lib32"
                        reshade_dir="${deckHome}/.config/reshade"
                        vkbasalt_dir="${deckHome}/.config/vkBasalt"
                        gamescope_reshade="${deckHome}/.local/share/gamescope/reshade"

                        mkdir -p "$lib_dir" "$lib32_dir" \
                                 "$reshade_dir/Shaders" "$reshade_dir/Textures" \
                                 "$vkbasalt_dir" \
                                 "$gamescope_reshade/Shaders" "$gamescope_reshade/Textures"

                        # vkBasalt shared libraries (FHS binaries — only work inside
                        # Steam's FHS sandbox where libX11/libstdc++ are available)
                        cp "$bv/vkBasalt.64/libvkbasalt.so" "$lib_dir/"
                        cp "$bv/vkBasalt.32/libvkbasalt.so" "$lib32_dir/"

                        # vkBasalt config
                        ${pkgs.gnused}/bin/sed \
                          -e "s|/path/to/reshade-shaders|$reshade_dir|" \
                          -e "s|/path/to/sombrero|$reshade_dir/Shaders/Sombrero.frag|" \
                          "$bv/config/vkBasalt.conf" > "$vkbasalt_dir/vkBasalt.conf"

                        # Reshade shaders and textures
                        cp "$bv"/*.frag "$bv"/*.fx* "$reshade_dir/Shaders/" 2>/dev/null || true
                        cp "$bv"/*.png "$reshade_dir/Textures/" 2>/dev/null || true

                        # Gamescope reshade shaders and textures
                        cp "$bv"/*.frag "$bv"/*.fx* "$gamescope_reshade/Shaders/" 2>/dev/null || true
                        cp "$bv"/*.png "$gamescope_reshade/Textures/" 2>/dev/null || true
                      fi
                      rm -rf "$tmp_extract"
                      manifest_checksum=$(sha256sum "$manifest_dir/manifest" 2>/dev/null | cut -d' ' -f1 || echo "")

                      # Create the verification shim
                      bin_dir="${deckHome}/.local/bin"
                      mkdir -p "$bin_dir"
                      cat > "$bin_dir/breezy_vulkan_verify" << 'VERIFY'
          #!/bin/sh
          echo "Verification succeeded"
          VERIFY
                      chmod 755 "$bin_dir/breezy_vulkan_verify"

                      # Pre-populate plugin settings so it accepts the NixOS install
                      mkdir -p "${settingsDir}"
                      cat > "${settingsDir}/settings.json" << SETTINGS
          {
            "installed_from_plugin_version": "$plugin_version",
            "manifest_checksum": "$manifest_checksum"
          }
          SETTINGS

                      # Patch plugin Python files to work on NixOS. Always patch
                      # from .orig backups so re-running is idempotent.
                      deck_uid=$(id -u deck 2>/dev/null || echo "1000")
                      for py_file in \
                        "${pluginDir}/main.py" \
                        "${pluginDir}/PyXRLinuxDriverIPC/xrdriveripc.py"
                      do
                        if [ -f "$py_file" ]; then
                          if [ ! -f "$py_file.orig" ]; then
                            cp "$py_file" "$py_file.orig"
                          fi
                          cp "$py_file.orig" "$py_file"
                          ${pkgs.gnused}/bin/sed -i "s|/run/user/1000|/run/user/$deck_uid|g" "$py_file"
                        fi
                      done

                      # Patch main.py: replace is_driver_running (needs user bus at
                      # boot) with a unit-file existence check.
                      ${pkgs.python3}/bin/python3 - "${pluginDir}/main.py" << 'PYEOF'
          import re, sys
          path = sys.argv[1]
          with open(path) as f:
              src = f.read()
          src = re.sub(
              r"(    async def is_driver_running\(self\):)\n.*?(?=\n    async def )",
              "\\1\n"
              "        import glob\n"
              "        return bool(glob.glob('/etc/systemd/user/xr-driver.service'))\n",
              src, count=1, flags=re.DOTALL,
          )
          with open(path, "w") as f:
              f.write(src)
          PYEOF


                      # Remove stale no-autostart drop-in from earlier config
                      rm -f "${deckHome}/.config/systemd/user/xr-driver.service.d/no-autostart.conf"

                      # Clean up stale /tmp IPC files from other users. The xrDriver
                      # binary opens these with O_CREAT, which fails under
                      # fs.protected_regular=1 if the file is owned by a different
                      # user in a sticky-bit directory (/tmp).
                      rm -f /tmp/shader_runtime_* /dev/shm/xr_driver_control /dev/shm/breezy_desktop_imu

                      # Fix ownership
                      chown -R deck:users "${deckHome}/.local"
                      chown -R deck:users "${settingsDir}"

                      echo "breezyDeckyShim: configured for plugin v$plugin_version (deck uid=$deck_uid)"
                    fi
                  fi
        '';
    };
}
