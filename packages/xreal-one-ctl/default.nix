# xreal_one_ctl — CLI tool for XReal One AR glasses control
#
# Builds the xreal_one_ctl binary from the xr-tools workspace.
# Primary use: enable-camera, which turns on the passthrough eye camera
# on the XReal One Pro and causes the device to reconnect with a UVC camera.
#
# The crate is part of a Cargo workspace; cargoRoot stays at the workspace
# root so importCargoLock finds the workspace Cargo.lock (vendored here as
# ./Cargo.lock). cargoBuildFlags restricts the build to this one binary.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  hidapi,
  pkg-config,
  udev,
  ...
}:
rustPlatform.buildRustPackage {
  pname = "xreal-one-ctl";
  version = "unstable-2025-07-24";

  src = fetchFromGitHub {
    owner = "0xcaff";
    repo = "xr-tools";
    rev = "2a6c5354081ce3a2e15ed325102ec424449b2617";
    hash = "sha256-hDCEGa08KacQJObCtrYUlSc8rCPTJxcl7YdJg+hYcPk=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  # Build only the CLI binary, not the whole workspace
  buildAndTestSubdir = "packages/xreal_one_ctl";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    hidapi
    udev
  ];

  # Tests require hardware; skip them
  doCheck = false;

  meta = with lib; {
    description = "CLI tool for controlling XReal One AR glasses (enable passthrough camera, etc.)";
    homepage = "https://github.com/0xcaff/xr-tools";
    license = licenses.mit;
    mainProgram = "xreal_one_ctl";
    platforms = platforms.linux;
  };
}
