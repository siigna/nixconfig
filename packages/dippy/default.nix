# Dippy — Claude Code PreToolUse hook that auto-approves shell commands it can
# prove are read-only, using a vendored pure-Python bash parser (Parable).
#
# No runtime dependencies, so this skips the uv_build backend and keeps the
# checkout layout: upstream's bin/dippy-hook puts ../src on sys.path itself.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  python3,
  ...
}:
stdenvNoCC.mkDerivation {
  pname = "dippy";
  version = "0.2.7-unstable-2026-06-12";

  src = fetchFromGitHub {
    owner = "ldayton";
    repo = "Dippy";
    rev = "2edad4a48d616a191c83417552ddc60eb79b526a";
    hash = "sha256-kyWIefFatT0C9D63PQ1lKAWTGoAgZtkXCo5bjuikRg4=";
  };

  buildInputs = [ python3 ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/dippy $out/bin
    cp -r bin src $out/lib/dippy/
    ln -s $out/lib/dippy/bin/dippy-hook $out/bin/dippy
    runHook postInstall
  '';

  meta = {
    description = "Auto-approve safe bash commands in Claude Code";
    homepage = "https://github.com/ldayton/Dippy";
    license = lib.licenses.mit;
    mainProgram = "dippy";
  };
}
