# claude-plugins — a local Claude Code plugin marketplace assembled from pinned
# upstream sources.
#
# The claude-code module registers this store path as a "directory"
# marketplace in /etc/claude-code/managed-settings.json and enables each
# plugin, so Claude Code installs them on the next session start without any
# /plugin commands. `make update` does not touch these pins; bump the revs here.
#
# Plugins:
#   cc-safety-net   PreToolUse hook blocking destructive commands and secret
#                   reads. Its hook calls bare `node`; pinned to our nodejs.
#   terraform-skill Terraform/OpenTofu skill. Upstream ships no Claude plugin
#                   manifest, so the marketplace entry is non-strict and only
#                   the skill directory is copied (its mcp.json would pull a
#                   Docker image).
#   skill-codex     Lets Claude delegate prompts to the Codex CLI.
#   agnix           /agnix command + skill wrapping the agnix linter.
#   trailofbits/*   Selected security-review plugins (tobPlugins below); none
#                   of them install hooks.
{
  lib,
  runCommand,
  fetchFromGitHub,
  nodejs,
  agnix,
  ...
}:
let
  safetyNet = fetchFromGitHub {
    owner = "kenryu42";
    repo = "claude-code-safety-net";
    rev = "f405293f0d4849a48bd023f7077e9fb1c28e3a38";
    hash = "sha256-mCEnQefzzn6oE2LTxkPivEaOfrCrVSdk23kjwv0OvkQ=";
  };

  terraformSkill = fetchFromGitHub {
    owner = "antonbabenko";
    repo = "terraform-skill";
    rev = "0a3a4a66e99001347d36a41e10260a825be3ab62";
    hash = "sha256-utKu3sueu6SdhjmtRa+Osg761YPwdQa6IPhceZsgsn8=";
  };

  skillCodex = fetchFromGitHub {
    owner = "skills-directory";
    repo = "skill-codex";
    rev = "0cf3e4b6e801cae209fc27a50440b453b44af910";
    hash = "sha256-+rsVc5J1JBsknIPB83zHNNTjFEycZPytWH5p4cd4g80=";
  };

  trailofbits = fetchFromGitHub {
    owner = "trailofbits";
    repo = "skills";
    rev = "442fc9d6c89b1e937e6f7a477e7071ea75fcbea4";
    hash = "sha256-Ih86JnI1tw5YIswdK38biz2tcaUZ5rPV143hzZViCxE=";
  };

  tobPlugins = [
    "audit-context-building"
    "c-review"
    "differential-review"
    "dwarf-expert"
    "insecure-defaults"
    "rust-review"
    "semgrep-rule-creator"
    "sharp-edges"
    "static-analysis"
    "supply-chain-risk-auditor"
    "variant-analysis"
    "yara-authoring"
  ];

  plugin =
    name: extra:
    {
      inherit name;
      source = "./plugins/${name}";
    }
    // extra;

  marketplace = {
    name = "nix-plugins";
    owner.name = "nix-config";
    metadata.description = "Claude Code plugins pinned by nix-config";
    plugins = [
      (plugin "cc-safety-net" { })
      (plugin "terraform-skill" {
        description = "Terraform and OpenTofu best practices";
        # Claude Code keys its plugin cache by version; without one it is
        # "unknown". Keep in step with upstream's version.json when bumping rev.
        version = "1.17.1";
        strict = false;
      })
      (plugin "skill-codex" { })
      (plugin "agnix" { })
    ]
    ++ map (n: plugin n { }) tobPlugins;
  };
in
runCommand "claude-plugins"
  {
    marketplaceJson = builtins.toJSON marketplace;
    passAsFile = [ "marketplaceJson" ];
    # Lets the claude-code module enable every plugin without reading the
    # built marketplace.json back (which would be import-from-derivation).
    passthru.pluginNames = map (p: p.name) marketplace.plugins;
  }
  ''
    mkdir -p $out/.claude-plugin $out/plugins
    cp $marketplaceJsonPath $out/.claude-plugin/marketplace.json

    cp -r ${safetyNet} $out/plugins/cc-safety-net
    chmod -R u+w $out/plugins/cc-safety-net
    substituteInPlace $out/plugins/cc-safety-net/hooks/hooks.json \
      --replace-fail '"node ' '"${lib.getExe nodejs} '

    mkdir -p $out/plugins/terraform-skill
    cp -r ${terraformSkill}/skills $out/plugins/terraform-skill/

    cp -r ${skillCodex}/plugins/skill-codex $out/plugins/skill-codex
    cp -r ${agnix.src}/plugin $out/plugins/agnix

    ${lib.concatMapStrings (n: ''
      cp -r ${trailofbits}/plugins/${n} $out/plugins/${n}
    '') tobPlugins}
  ''
