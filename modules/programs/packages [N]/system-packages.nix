{ ... }:
{
  flake.modules.nixos.system-packages =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        arduino bind direnv ec2-api-tools element-desktop awscli2
        exiftool figlet file findutils firefox fwupd gcc freecad
        git gjs dconf-editor gnome-tweaks gnumake
        google-chrome htop imagemagick inkscape-with-extensions iotop
        jq libinput libossp_uuid
        mergerfs mergerfs-tools mkpasswd mlocate ncdu fastfetch nheko niv
        nvme-cli openscad parted plex-desktop
        prusa-slicer rpmextract scrcpy screen spotify
        telegram-desktop tmate tmux tree unzip usbutils vim virt-manager
        fluffychat adwaita-qt adwaita-qt6 libadwaita
        pv mosh git-crypt gnome-network-displays qelectrotech
        vscodium-fhs neovim galileo-mura blackbox-terminal zoom-us
        linux-wifi-hotspot ocrmypdf qpdf docker-compose duckdb nodejs_22
        gnumeric gimp-with-plugins dbeaver-bin woeusb-ng testdisk
        ddrescue mpv ventoy-full dune3d glib quickemu atop winetricks
        qrencode zint-qt opentofu zip cargo-lambda rustup httptoolkit cargo-audit
        cargo-llvm-cov cargo-nextest cargo-make rust-analyzer inetutils
        shellcheck qjournalctl ascii-image-converter
        nix-tree esptool gnomeExtensions.tactile gnomeExtensions.caffeine cmatrix
        unityhub tytools netflix bambu-studio bottles-unwrapped claude-code
        rustscan nmap binwalk ffmpeg attic-client android-tools discord
        nix-sweep
        (python313.withPackages (ps: with ps; [
          numpy
          scipy
          jupyterlab
          pandas
          statsmodels
          scikit-learn
          matplotlib
          seaborn
          babel
          ipython
          pip
          yfinance
          pipenv
        ]))
        (vscode-with-extensions.override {
          vscodeExtensions = with vscode-extensions; [
            ms-python.python
            svelte.svelte-vscode
            vscodevim.vim
          ] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
            {
              name = "evidence-vscode";
              publisher = "Evidence";
              version = "1.5.6";
              sha256 = "uRiv3aarSeY8kHYeKYQzhDCEn16ZErgKQTUGoZtFuPc=";
            }
            {
              name = "sqltools";
              publisher = "mtxr";
              version = "0.28.3";
              sha256 = "sha256-bTrHAhj8uwzRIImziKsOizZf8+k3t+VrkOeZrFx7SH8=";
            }
            {
              name = "chatgpt";
              publisher = "openai";
              version = "0.5.18";
              sha256 = "sha256-E/bv4uPppl/M+8Uvs0eap9w4EDOqA33rpQusyb5dgds=";
            }
          ];
        })
      ];

      virtualisation.libvirtd.enable = true;
      virtualisation.docker.enable = true;
      programs.dconf.enable = true;
      programs.steam.enable = true;
      programs.wshowkeys.enable = true;
      programs.bcc.enable = true;
      programs.appimage = {
        enable = true;
        binfmt = true;
      };
      programs.kdeconnect = {
        enable = true;
        package = pkgs.gnomeExtensions.gsconnect;
      };
      programs.bash.interactiveShellInit = ''eval "$(direnv hook bash)"'';
    };
}
