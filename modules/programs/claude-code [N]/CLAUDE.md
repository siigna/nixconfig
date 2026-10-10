# claude-code.nix notes

Claude Code is configured system-wide through `/etc/claude-code/managed-settings.json`, which sits
above `~/.claude/settings.json`: single keys set here (e.g. `statusLine`) win, while lists such as
`hooks` and `permissions.allow` merge with the user's. Do **not** add `allowManagedHooksOnly`,
`strictKnownMarketplaces` or a `managed-mcp.json` — each one locks out the user-level plugins
(caveman etc.) or the project's MCP servers.

What it sets:

- **statusLine** — `goccc -statusline`. Upstream goccc misprices OpenRouter transcripts
  (`anthropic/claude-opus-5.5`), hence `packages/goccc/openrouter-model-ids.patch`. Layout is
  configurable in `~/.goccc.json`.
- **PreToolUse hook (Bash)** — Dippy, wrapped so its `ask` verdicts are dropped. A hook answering
  `ask` forces a prompt even in auto mode, so only `allow`/`deny` pass through and everything else
  takes the normal permission path.
- **`nix-plugins` marketplace** — a `directory` marketplace pointing at the `claude-plugins` store
  path, with every plugin in it enabled. Claude Code installs them at the next session start and
  copies each into `~/.claude/plugins/cache/nix-plugins/<name>/<version>/`. The cache is keyed by
  plugin version, so a rev bump that keeps the same version may need `/plugin` → reinstall.

cc-safety-net (from the marketplace) is the deny side: it blocks destructive git/rm commands and
reads of SSH keys, `.env` files and similar, from both Bash and the file tools. Its policy can be
tuned per project in `.cc-safety-net/`.
