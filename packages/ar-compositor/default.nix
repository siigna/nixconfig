# ar-compositor — AR passthrough compositor for Xreal One Pro
#
# GTK3 + GStreamer app that composites the glasses camera feed with a
# Mutter ScreenCast capture of the desktop, with live preview and recording.
{
  lib,
  python3Packages,
  gst_all_1,
  gtk3,
  pipewire,
  gobject-introspection,
  wrapGAppsHook3,
  ...
}:
python3Packages.buildPythonApplication {
  pname = "ar-compositor";
  version = "unstable";

  src = ./.;

  format = "other";

  nativeBuildInputs = [
    wrapGAppsHook3
    gobject-introspection
  ];

  buildInputs = [
    gtk3
    pipewire
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
    gst_all_1.gst-libav
  ];

  propagatedBuildInputs = with python3Packages; [
    pygobject3
  ];

  installPhase = ''
    install -Dm755 ar-compositor.py $out/bin/ar-compositor
    install -Dm644 /dev/stdin $out/share/applications/ar-compositor.desktop <<EOF
    [Desktop Entry]
    Name=AR Compositor
    Comment=AR passthrough compositor for Xreal One Pro glasses
    Exec=ar-compositor
    Icon=video-display
    Terminal=false
    Type=Application
    Categories=Utility;
    EOF
  '';

  meta = with lib; {
    description = "AR passthrough compositor for Xreal One Pro glasses";
    license = licenses.mit;
    mainProgram = "ar-compositor";
    platforms = platforms.linux;
  };
}
