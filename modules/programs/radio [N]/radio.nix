{ ... }:
{
  flake.modules.nixos.radio =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        #chirp
        cubicsdr
        #direwolf
        fldigi
        #freedv
        #gqrx
        #multimon-ng
        rtl-sdr
        #sdrangel
        #soapysdr-with-plugins
      ];

      # Enable RTL SDR
      hardware.rtl-sdr.enable = true;
    };
}
