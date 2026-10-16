{ ... }:
{
  # atop with long-term datalogging, plus an hourly atopsar text report served over HTTP.
  # Reports land in /var/lib/atop-reports/<YYYYMMDD>/<HH>.txt (latest.txt = copy of newest) and are
  # served on port 8088. The firewall only trusts tailscale0, so that's tailnet-only.
  flake.modules.nixos.atop =
    { config, pkgs, lib, ... }:
    let
      atop = config.programs.atop.package;
      logPath = "/var/log/atop";
      reportDir = "/var/lib/atop-reports";
      reportPort = 8088;
      keepDays = 28; # matches atop's own LOGGENERATIONS default for raw logs

      hourlyReport = pkgs.writeShellApplication {
        name = "atop-hourly-report";
        runtimeInputs = [
          atop
          pkgs.coreutils
          pkgs.findutils
        ];
        text = ''
          # Report on the previous full hour. atop-rotate starts a new raw file at midnight, so the
          # hour's own date picks the right file even for 23:00.
          stamp=$(date -d '1 hour ago' +%Y%m%d%H)
          day=''${stamp:0:8}
          hour=''${stamp:8:2}
          log="${logPath}/atop_$day"
          [ -e "$log" ] || { echo "no atop log $log yet"; exit 0; }

          out="${reportDir}/$day"
          mkdir -p "$out"
          {
            echo "${config.networking.hostName} atop report for $day $hour:00-$hour:59 (5-minute buckets)"
            echo
            # -R 5 averages five 60 s samples per row. CPU: keep the "all" row, drop the 12
            # per-thread rows atopsar prints under it.
            atopsar -r "$log" -b "$hour:00" -e "$hour:59" -R 5 -c | grep -vE '^ +[0-9]+ +[0-9]'
            # p=load m=memory s=swap d=disk i=network; O/G/D = top-3 processes by CPU/memory/disk.
            atopsar -r "$log" -b "$hour:00" -e "$hour:59" -R 5 -pmsdi -O -G -D
          } > "$out/$hour.txt.tmp"
          mv "$out/$hour.txt.tmp" "$out/$hour.txt"
          # A copy, not a symlink: static-web-server answers 403 for symlinks.
          cp "$out/$hour.txt" "${reportDir}/latest.txt.tmp"
          mv "${reportDir}/latest.txt.tmp" "${reportDir}/latest.txt"

          find "${reportDir}" -mindepth 1 -maxdepth 1 -type d -mtime +${toString keepDays} -exec rm -rf {} +
        '';
      };
    in
    {
      programs.atop = {
        enable = true;
        atopService.enable = true;
        # Process accounting: catches short-lived processes (compilers during remote builds)
        # that start and exit between two samples.
        atopacctService.enable = true;
        atopRotateTimer.enable = true;
      };

      # Default is one sample per 600 s; 60 s gives the hourly report real resolution.
      systemd.services.atop.environment.LOGINTERVAL = lib.mkForce "60";

      systemd.services.atop-hourly-report = {
        description = "Write the previous hour's atopsar report";
        after = [ "atop.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe hourlyReport;
          StateDirectory = "atop-reports";
          StateDirectoryMode = "0755";
        };
      };
      systemd.timers.atop-hourly-report = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* *:02:00";
          Persistent = true;
        };
      };

      services.static-web-server = {
        enable = true;
        listen = "[::]:${toString reportPort}";
        root = reportDir;
        configuration.general.directory-listing = true;
      };
      # SWS refuses to start if its root doesn't exist yet (first boot before the first report).
      systemd.tmpfiles.rules = [ "d ${reportDir} 0755 root root -" ];
    };
}
