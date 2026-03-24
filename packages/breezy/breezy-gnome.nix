# Breezy Desktop GNOME component — extension + settings UI + virtualdisplay.
#
# Build structure: the top-level repo uses CMake for the full system, but only
# the ui/ subdirectory is a Meson project. We run `meson setup` inside ui/ and
# compile only that subtree; the CMake top-level is not invoked here.
#
# Symlink resolution in buildPhase: the gnome/src directory contains symlinks
# that point into sibling subdirectories of the monorepo (schemas, textures,
# shader sources). These are resolved by explicitly copying the targets over the
# symlinks before compiling schemas or packaging the extension. The unlink+cp
# sequence is intentional — patch or substituteInPlace would follow the symlink
# and modify the source, which fails in the Nix sandbox.
#
# Python wrapping: the breezydesktop binary is a compiled GResource bundle that
# spawns Python scripts from the same package. There are no setuptools entry
# points, so we manually detect Python shebangs and call wrapProgram to inject
# PYTHONPATH, APPDIR, and BINDIR. The --skip-verification flag suppresses the
# upstream check for `breezy_gnome_verify`, which is produced by the bash
# installer and doesn't exist in the Nix build.
#
# Extension path rewrite: extension.js hardcodes /usr/bin/xr_driver_cli for the
# keyboard toggle shortcut. substituteInPlace rewrites it to the Nix store path.
# Note: the GNOME extension also looks at $XDG_BIN_HOME/xr_driver_cli (i.e.
# ~/.local/bin/) — a symlink there is needed on NixOS because that dir is on
# PATH for the user but $out/bin is not unless added explicitly.
{
  source,
  lib,
  stdenv,
  meson,
  ninja,
  cmake,
  glib,
  gtk4,
  pkg-config,
  pipewire,
  libadwaita,
  python3,
  python3Packages,
  gst_all_1,
  curlFull,
  wrapGAppsHook4,
  desktop-file-utils,
  appstream,
  xrlinuxdriver,
  fd,
  ...
}:
let
  uuid = "breezydesktop@xronlinux.com";
in
stdenv.mkDerivation rec {
  pname = "breezy-gnome";

  inherit (source) version src;

  buildInputs = [
    glib
    glib.dev
    gtk4
    pipewire
    libadwaita
    python3
    python3Packages.pygobject3
    python3Packages.pydbus
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    curlFull.dev
    desktop-file-utils
    appstream
    xrlinuxdriver
  ];

  nativeBuildInputs = [
    meson
    ninja
    cmake
    pkg-config
    wrapGAppsHook4
  ];

  passthru = {
    extensionUuid = uuid;
  };

  # connected-device.ui has two GtkBox widgets with orientation=2, which is
  # not a valid GtkOrientation value (only 0=horizontal, 1=vertical exist).
  # This causes a GLib critical on template init and the app exits immediately.
  # Bug in breezy-desktop v2.9.11 — the intended value is clearly "vertical".
  postPatch = ''
    substituteInPlace ui/src/gtk/connected-device.ui \
      --replace-warn '<property name="orientation">2</property>' '<property name="orientation">vertical</property>'

    # Wrap main_content in a GtkScrolledWindow so the window is vertically
    # scrollable. main_content id must stay on the inner GtkBox because
    # window.py references it as a Template.Child.
    patch -p1 < ${./window-scrollable.patch}
  '';

  configurePhase = ''
    cd ui
    meson setup build
    cd ..
  '';

  buildPhase = ''
    cd ui/build
    meson compile

    cd ../..

    unlink gnome/src/schemas/com.xronlinux.BreezyDesktop.gschema.xml
    cp ui/data/com.xronlinux.BreezyDesktop.gschema.xml gnome/src/schemas/
    mkdir -p build/schemas
    glib-compile-schemas --targetdir="build/schemas/" "$src/gnome/src/schemas/"

    unlink gnome/src/textures/custom_banner.png
    cp vulkan/custom_banner.png gnome/src/textures/

    unlink gnome/src/textures/calibrating.png
    cp modules/sombrero/calibrating.png gnome/src/textures/

    unlink gnome/src/Sombrero.frag
    cp modules/sombrero/Sombrero.frag gnome/src/
  '';

  installPhase = ''
    mkdir -p "$out/share/glib-2.0/schemas"
    cp ui/data/com.xronlinux.BreezyDesktop.gschema.xml $out/share/glib-2.0/schemas/
    cp build/schemas/* $out/share/glib-2.0/schemas/

    mkdir -p "$out/share/gnome-shell/extensions/"
    cp -r "./gnome/src" "$out/share/gnome-shell/extensions/${uuid}"
    cp -r build/schemas "$out/share/gnome-shell/extensions/${uuid}/"
    substituteInPlace "$out/share/gnome-shell/extensions/${uuid}/extension.js" \
      --replace "/usr/bin/xr_driver_cli" '${xrlinuxdriver}/bin/xr_driver_cli'

    mkdir -p "$out/${python3.sitePackages}/breezydesktop/"
    cp -r ui/src/*.py "$out/${python3.sitePackages}/breezydesktop/"
    cp -r ui/modules/PyXRLinuxDriverIPC/*.py "$out/${python3.sitePackages}/breezydesktop/"

    mkdir -p "$out/share/locale/"
    cp -r ui/po/mo/* "$out/share/locale/"

    mkdir -p $out/bin
    cp ui/build/src/breezydesktop $out/bin/
    cp ui/build/src/virtualdisplay $out/bin/

    install -Dm755 ui/build/src/breezydesktop.gresource $out/share/breezydesktop/breezydesktop.gresource
    install -Dm755 ui/build/data/com.xronlinux.BreezyDesktop.desktop $out/share/applications/com.xronlinux.BreezyDesktop.desktop

    # Wrap all Python scripts to use the right PYTHONPATH.
    # --skip-verification bypasses the check for 'breezy_gnome_verify', which
    # is part of the upstream bash installer and doesn't exist in the Nix build.
    for f in $out/bin/*; do
      if head -n 1 "$f" | grep -q python; then
        extraFlags=""
        if [[ "$(basename $f)" == "breezydesktop" ]]; then
          extraFlags="--add-flags --skip-verification"
        fi
        wrapProgram "$f" \
          --set PYTHONPATH "$out/${python3.sitePackages}:${python3Packages.pygobject3}/${python3.sitePackages}:${python3Packages.pydbus}/${python3.sitePackages}" \
          --set APPDIR "$out/share" \
          --set BINDIR "$out/bin" \
          $extraFlags
      fi
    done
  '';

  doInstallCheck = false;
  # The default release is a script which will do an impure download
  # just ensure that the application can run without network

  meta = with lib; {
    homepage = "https://github.com/wheaney/breezy-desktop";
    platforms = platforms.linux;
  };
}
