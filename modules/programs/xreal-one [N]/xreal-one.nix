{ ... }:
{
  flake.modules.nixos.xreal-one =
    { pkgs, ... }:
    {
      # Install the xreal_one_ctl binary so the user can run:
      #   xreal_one_ctl enable-camera   # turns on the passthrough eye camera
      #   xreal_one_ctl --help          # see all commands
      #
      # After enable-camera, the XReal One Pro disconnects and reconnects with
      # an additional UVC camera device that apps like OBS can access.
      environment.systemPackages = [ pkgs.xreal-one-ctl ];

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
