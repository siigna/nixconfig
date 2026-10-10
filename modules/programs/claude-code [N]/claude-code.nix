{ ... }:
{
  flake.modules.nixos.claude-code =
    { pkgs, lib, ... }:
    let
      # Dippy answers "ask" for every command it cannot prove read-only. An
      # explicit ask forces a prompt even in auto mode, where the classifier
      # would otherwise have approved it, so only its allow/deny verdicts are
      # passed through; everything else falls back to the normal permission flow.
      dippyHook = pkgs.writeShellApplication {
        name = "dippy-hook";
        runtimeInputs = [
          pkgs.dippy
          pkgs.jq
        ];
        text = ''
          out=$(dippy) || exit $?
          if jq -e '.hookSpecificOutput.permissionDecision == "ask"' <<<"$out" >/dev/null 2>&1; then
            exit 0
          fi
          printf '%s\n' "$out"
        '';
      };

      marketplace = "nix-plugins";
      pluginIds = map (p: "${p}@${marketplace}") pkgs.claude-plugins.pluginNames;

      # Managed settings sit above ~/.claude/settings.json: single keys here win,
      # lists (hooks, permissions) merge with the user's. Deliberately no
      # allowManagedHooksOnly or managed-mcp.json — both would lock out the
      # user-level plugins and MCP servers.
      settings = {
        statusLine = {
          type = "command";
          command = "${lib.getExe pkgs.goccc} -statusline";
        };
        hooks.PreToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = lib.getExe dippyHook;
              }
            ];
          }
        ];
        extraKnownMarketplaces.${marketplace}.source = {
          source = "directory";
          path = "${pkgs.claude-plugins}";
        };
        enabledPlugins = lib.genAttrs pluginIds (_: true);
      };
    in
    {
      environment.systemPackages = with pkgs; [
        claude-code
        goccc
        agnix
        # Called by the Trail of Bits skills (static-analysis, yara-authoring, …).
        # codeql is unfree: free for open-source code and research only.
        uv
        semgrep
        codeql
      ];

      environment.etc."claude-code/managed-settings.json".text = builtins.toJSON settings;
    };
}
