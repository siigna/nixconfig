{
  source,
  lib,
  stdenv,
  fetchFromGitLab,
  rustPlatform,
  udev,
  libusb1,
  curl,
  openssl,
  libevdev,
  json_c,
  hidapi,
  wayland,
  cmake,
  pkg-config,
  python3,
  libffi,
  autoPatchelfHook,
  cargo,
  rustc,
  ...
}:
let
  pythonEnv = python3.withPackages (ps: [ ps.pyyaml ]);
  cargoRoot = "modules/xrealInterfaceLibrary/interface_lib/modules/xreal_one_driver";
  cargoDeps = rustPlatform.importCargoLock {
    lockFile = "${source.src}/modules/XRLinuxDriver/${cargoRoot}/Cargo.lock";
  };
  buildInputs = [
    curl
    hidapi
    json_c
    libevdev
    libffi
    libusb1
    openssl
    stdenv.cc.cc.lib
    udev
    wayland
  ];
  arch =
    if stdenv.hostPlatform.system == "aarch64-linux" then
      "aarch64"
    else if stdenv.hostPlatform.system == "x86_64-linux" then
      "x86_64"
    else
      throw "Unsupported system ${stdenv.hostPlatform.system}";
in
stdenv.mkDerivation rec {
  pname = "xrlinuxdriver";
  inherit (source) version;

  src = "${source.src}/modules/XRLinuxDriver";

  nativeBuildInputs = [
    cmake
    pkg-config
    pythonEnv
    autoPatchelfHook
    cargo
    rustc
    rustPlatform.cargoSetupHook
  ];

  inherit cargoDeps cargoRoot;
  inherit buildInputs;

  patches = [
    # pthread_mutex_destroy returns EPERM when the GNOME extension still
    # holds an mmap on the shared memory segment. The mutex is about to
    # be reinitialized anyway, so treat EPERM (and EOWNERDEAD) as non-fatal
    # like EINVAL already is.
    ./ipc-mutex-robust.patch

    # Watch the config directory for MOVED_TO instead of the file for
    # DELETE_SELF. Tools like xr_driver_cli and Breezy Desktop use
    # os.replace() (atomic rename) which creates a new inode; the old
    # inotify watch on the file never fires.
    ./config-inotify-directory.patch

    # write_state calls fopen then fprintf without a NULL check. Under
    # fs.protected_regular=1, fopen fails if the state file in /dev/shm
    # is owned by a different user, causing a segfault in fprintf(NULL).
    ./state-null-check.patch

    # When re-enabling the driver via config change, the device thread
    # stays blocked because the logical disconnect cleared device_present().
    # Force-unblock it so it reconnects to the physically present device.
    ./reenable-device-reconnect.patch

    # At startup, update_config_from_file() runs before plugins.start().
    # device_license_start_func() makes a synchronous network request to fetch
    # granted_features, so is_productivity_granted() is cached as false when the
    # config is first parsed — breezy_desktop.enabled stays false even with a
    # valid trial/paid license. Re-reading the config after plugins.start() fixes
    # the race so breezy desktop actually enables on startup without needing the
    # user to manually re-trigger a config change.
    ./startup-license-race.patch
  ];

  cmakeFlags = [
    "-DCMAKE_SKIP_RPATH=ON"
    "-DCMAKE_EXE_LINKER_FLAGS=-ludev"
  ];
  cmakeBuildDir = "build";
  cmakeBuildType = "RelWithDebInfo";

  installPhase = ''
    mkdir -p $out/bin $out/lib/systemd/user $out/lib/udev/rules.d $out/lib/${arch}
    cp xrDriver ../bin/xr_driver_cli ../bin/xr_driver_verify $out/bin
    cp ../udev/* $out/lib/udev/rules.d/
    cp -r ../lib/${arch}/* $out/lib/${arch}/
    cp ../systemd/xr-driver.service $out/lib/systemd/user/
    cp ${hidapi}/lib/libhidapi-hidraw.so.0 $out/lib/

    substituteInPlace $out/lib/systemd/user/xr-driver.service \
      --replace '{bin_dir}' "$out/bin" \
      --replace '{ld_library_path}' "$out/lib/${arch}"
  '';

  preBuild = ''
    addAutoPatchelfSearchPath $out/lib/${arch}
  '';

  doInstallCheck = false;
  # The default release is a script which will do an impure download
  # just ensure that the application can run without network

  meta = with lib; {
    homepage = "https://github.com/wheaney/XRLinuxDriver";
    license = licenses.mit;
    description = "Linux service for interacting with XR devices.";
    mainProgram = "xrDriver";
    # maintainers = with maintainers; [shymega];
    platforms = platforms.linux;
  };
}
