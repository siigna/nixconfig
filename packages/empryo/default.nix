# Empryo (formerly SoulForge) — terminal AI coding agent. Prebuilt Bun binary
# from dl.empryo.com; upstream ships no source.
#
# The binary finds its runtime payload (wasm, opentui-assets, native, init.lua)
# at dirname(execPath)/deps and hydrates it into a content-addressed dir under
# ~/.empryo/runtime/ on first start, so the tarball layout is kept intact under
# libexec. Not stripped: Bun keeps the compiled app in the `.bun` ELF section.
#
# The bundled rg/fd/lazygit are dropped in favour of nixpkgs ones on PATH; addons
# Empryo would otherwise download (ast-grep, neovim) are put there too, since its
# downloaded glibc binaries won't run on NixOS.
{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  ripgrep,
  fd,
  lazygit,
  ast-grep,
  neovim,
  ...
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "empryo";
  version = "3.11.0-beta";

  # The standard x64 build needs AVX2/FMA/BMI2; the Deck's Zen 2 has them.
  src = fetchurl {
    url = "https://dl.empryo.com/v${finalAttrs.version}/empryo-${finalAttrs.version}-linux-x64.tar.gz";
    hash = "sha256-uceYlQ+Pj14VF/8eDeT2TVoU58Cq4qxnjN03fkdX1N4=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec/empryo $out/share/licenses/empryo
    install -Dm755 empryo $out/libexec/empryo/empryo
    rm deps/rg deps/fd deps/lazygit
    cp -r deps $out/libexec/empryo/deps
    cp LICENSE THIRD_PARTY_LICENSES.md $out/share/licenses/empryo/

    makeWrapper $out/libexec/empryo/empryo $out/bin/empryo \
      --suffix PATH : ${
        lib.makeBinPath [
          ripgrep
          fd
          lazygit
          ast-grep
          neovim
        ]
      }
    ln -s empryo $out/bin/em

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    HOME=$TMPDIR $out/bin/empryo --version
  '';

  meta = {
    description = "Terminal AI coding agent (formerly SoulForge)";
    homepage = "https://empryo.com";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "empryo";
  };
})
