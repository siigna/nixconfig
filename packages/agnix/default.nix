# agnix — linter for agent config files (CLAUDE.md, SKILL.md, hooks, plugins,
# MCP config). Only the CLI crate is built; the LSP, MCP and WASM crates in the
# same workspace are skipped. Telemetry is a compile-time opt-in feature and
# stays off.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  ...
}:
rustPlatform.buildRustPackage {
  pname = "agnix";
  version = "0.57.0-unstable-2026-10-09";

  src = fetchFromGitHub {
    owner = "agent-sh";
    repo = "agnix";
    rev = "004b7ea143de549c13e89614fd73be0497abbdd0";
    hash = "sha256-jE/YqSG3LmFRl565rGRT/pq8JoXJzm1kiarhmv/HYaE=";
  };

  cargoHash = "sha256-HPT9qfhQnEq+aNzJwOYkdedprYDaPDMGPK0NcVZFETU=";

  cargoBuildFlags = [
    "-p"
    "agnix-cli"
  ];
  # The workspace test suite covers every crate, including the ones not built.
  doCheck = false;

  meta = {
    description = "Linter for AI coding assistant configuration";
    homepage = "https://github.com/agent-sh/agnix";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "agnix";
  };
}
