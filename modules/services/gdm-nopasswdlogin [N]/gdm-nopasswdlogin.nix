{ ... }:
{
  flake.modules.nixos.gdm-nopasswdlogin =
    { pkgs, ... }:
    {
      users.groups.nopasswdlogin = { };
      security.pam.services.gdm-password.text = pkgs.lib.mkBefore "auth sufficient pam_succeed_if.so user ingroup nopasswdlogin";
    };
}
