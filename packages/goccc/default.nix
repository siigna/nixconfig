# goccc — Claude Code cost calculator and statusline (single Go binary).
#
# Used as the Claude Code statusLine (see the claude-code module). Prices
# sessions from the local JSONL transcripts against an embedded pricing.json,
# refreshed from upstream in the background and cached.
#
# openrouter-model-ids.patch: transcripts written through OpenRouter record the
# model as "anthropic/claude-opus-5.5"; upstream only knows "claude-opus-5-5"
# and silently falls back to default pricing. The patch strips the vendor
# prefix and maps dots to dashes before lookup and display.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  ...
}:
buildGoModule rec {
  pname = "goccc";
  version = "unstable-2026-10-09";

  src = fetchFromGitHub {
    owner = "backstabslash";
    repo = "goccc";
    rev = "553f069a2095b7a9a11f7efa0936bcd141d5f50b";
    hash = "sha256-UN7q3liio9e/IiN9TQCsi1Py8NK2QHq4TA3MeKEJ3mA=";
  };

  patches = [ ./openrouter-model-ids.patch ];

  # No third-party dependencies (no go.sum).
  vendorHash = null;

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  meta = {
    description = "Claude Code cost calculator and statusline";
    homepage = "https://github.com/backstabslash/goccc";
    license = lib.licenses.mit;
    mainProgram = "goccc";
  };
}
