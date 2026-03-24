{ ... }:
{
  flake.modules.nixos.xreal-one =
    { pkgs, ... }:
    {
      # Install xreal_one_ctl and the AR compositor.
      #   xreal_one_ctl enable-camera   # turns on the passthrough eye camera
      #   ar-compositor                 # live AR passthrough + recording GUI
      environment.systemPackages = [
        pkgs.xreal-one-ctl
        pkgs.ar-compositor
      ];

      # Allow the user USB access to the XReal One device without sudo.
      # Vendor ID 0x3318 is XReal (formerly Nreal).
      services.udev.extraRules = ''
        # XReal One / One Pro — grant plugdev access for xreal_one_ctl
        SUBSYSTEM=="usb", ATTRS{idVendor}=="3318", MODE="0664", GROUP="plugdev"
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3318", MODE="0664", GROUP="plugdev"
      '';

      # Ensure the primary user is in plugdev
      users.users.siigna.extraGroups = [ "plugdev" ];
    };
}
