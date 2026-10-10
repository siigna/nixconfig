# gdm-nopasswdlogin.nix notes

The PAM rule must go through `security.pam.services.gdm-password.rules`, not `.text`. The generated
stack is `lib.mkDefault`, so any plain `text` definition (including `mkBefore`, which changes order
but not priority) discards it entirely — gdm-password then falls through to `/etc/pam.d/other`
(pam_warn + pam_deny) and every GDM login fails, including deck's autologin.
