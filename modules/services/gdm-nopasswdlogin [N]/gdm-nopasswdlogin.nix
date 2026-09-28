{ ... }:
{
  flake.modules.nixos.gdm-nopasswdlogin =
    { config, ... }:
    {
      users.groups.nopasswdlogin = { };

      # Let members of the nopasswdlogin group log into GDM without a password.
      #
      # This must go through `rules` rather than `security.pam.services.gdm-password.text`.
      # The generated stack is assigned as `lib.mkDefault` (priority 1000), so *any* plain
      # definition of `text` — including `mkBefore`, which only affects ordering within a
      # priority, not the priority itself — wins outright and discards the generated rules.
      # That leaves gdm-password with no account/password/session phases, so those fall
      # through to /etc/pam.d/other (pam_warn + pam_deny) and every GDM login fails,
      # including deck's autologin.
      security.pam.services.gdm-password.rules.auth.nopasswdlogin = {
        order = 10050; # before the "login" substack at 10100
        control = "sufficient";
        modulePath = "${config.security.pam.package}/lib/security/pam_succeed_if.so";
        args = [
          "user"
          "ingroup"
          "nopasswdlogin"
        ];
      };
    };
}
