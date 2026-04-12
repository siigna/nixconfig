# obdium — OBD-II vehicle diagnostics desktop app (Tauri v1 + Rust)
#
# Reads live sensor data and fault codes from vehicles via ELM327 USB-serial
# adapters. Embeds the HTML/CSS/JS frontend via the custom-protocol Tauri
# feature. The three bundled SQLite databases are installed to
# $out/share/obdium/data/ and a wrapper sets CWD so the relative
# ./data/*.sqlite paths in the Rust source resolve correctly.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  wrapGAppsHook,
  webkitgtk_4_0,
  gtk3,
  glib-networking,
  openssl,
  glib,
  dbus,
  udev,
  ...
}:
rustPlatform.buildRustPackage {
  pname = "obdium";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "provrb";
    repo = "obdium";
    rev = "98ec080920ff4af340dccf233f307c7e4c05bcce";
    hash = "sha256-iuvsKOIZPUMwZZxUdEtng/SHWb3+dHy64ZLXxb/dmGI=";
  };

  cargoRoot = "backend";
  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  # Embed the frontend (../frontend relative to backend/) into the binary.
  buildFeatures = [ "custom-protocol" ];

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook
  ];

  buildInputs = [
    webkitgtk_4_0
    gtk3
    glib-networking
    openssl
    glib
    dbus
    udev
  ];

  # Install the bundled SQLite databases. The Rust source opens them via the
  # relative path ./data/*.sqlite, so preFixup points CWD there at launch.
  postInstall = ''
    install -Dm644 $src/backend/data/vpic.sqlite \
      $out/share/obdium/data/vpic.sqlite
    install -Dm644 $src/backend/data/code-descriptions.sqlite \
      $out/share/obdium/data/code-descriptions.sqlite
    install -Dm644 $src/backend/data/model-pids.sqlite \
      $out/share/obdium/data/model-pids.sqlite
  '';

  # wrapGAppsHook wraps the binary; inject --chdir so ./data/*.sqlite resolves.
  preFixup = ''
    gappsWrapperArgs+=(--chdir "$out/share/obdium")
  '';

  doCheck = false;

  meta = with lib; {
    description = "OBD-II vehicle diagnostics app for reading live data via ELM327 adapters";
    homepage = "https://github.com/provrb/obdium";
    mainProgram = "obdium";
    platforms = platforms.linux;
  };
}
