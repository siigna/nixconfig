{ ... }:
{
  flake.modules.nixos.bootnext =
    { pkgs, ... }:
    {
      # Windows moves itself to the front of BootOrder whenever it boots. Put the entry we
      # booted from back in front. BootOrder survives hibernate resume; a one-shot BootNext
      # doesn't (the resume consumes it and this unit doesn't run again).
      systemd.services.bootnext-steamos = {
        description = "Move the current UEFI boot entry to the front of BootOrder";
        wantedBy = [ "multi-user.target" ];
        serviceConfig.Type = "oneshot";
        path = [ pkgs.efibootmgr ];
        script = ''
          info=$(efibootmgr)
          cur=$(sed -n 's/^BootCurrent: //p' <<<"$info")
          order=$(sed -n 's/^BootOrder: //p' <<<"$info")
          [ -n "$cur" ] || exit 0
          # Skip the NVRAM write when already first.
          case "$order" in "$cur" | "$cur",*) exit 0 ;; esac
          rest=$(tr , '\n' <<<"$order" | grep -vx "$cur" | paste -sd, || true)
          efibootmgr -o "$cur''${rest:+,$rest}"
        '';
      };
    };
}
