{ inputs, ... }:
{
  # Hermes Agent gateway: text the Telegram bot, the agent runs here (as the `hermes` user,
  # state in /var/lib/hermes) and replies. Model calls go to OpenRouter (Hermes' default).
  flake.modules.nixos.hermes = { pkgs, ... }: {
    # No one else in the `hermes` group: with another member, Hermes refuses its own control
    # socket (group-writable HERMES_HOME). Fetch Leonard's clone via sudo, see AGENTS.md.
    imports = [ inputs.hermes-agent.nixosModules.default ];

    services.hermes-agent = {
      enable = true;
      # Flake maintenance (AGENTS.md): build both hosts, no deploy rights.
      workingDirectory = "/var/lib/hermes/workspace"; # the module default; AGENTS.md cites it
      documents."AGENTS.md" = ./AGENTS.md;
      extraPackages = with pkgs; [
        nix
        nixfmt
        jq
        diffutils
        fwupd
      ];
      settings = {
        model.default = "anthropic/claude-sonnet-5.5";
        # Scheduled jobs don't need the chat model; unpinned jobs run on this.
        cron.model = "anthropic/claude-haiku-5.5";
        # Host-header (DNS-rebinding) guard only accepts the bound address plus this name.
        dashboard.public_url = "http://steammachine:9119";
      };
      # Not in the repo (public) and not in the store. Create on the box, root:root 0600:
      #   OPENROUTER_API_KEY=...
      #   TELEGRAM_BOT_TOKEN=...
      #   TELEGRAM_ALLOWED_USERS=<numeric Telegram user id>   # gateway is default-deny without it
      #   HERMES_DASHBOARD_BASIC_AUTH_USERNAME=...             # a non-loopback dashboard refuses
      #   HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=...             # to start without these
      #   HERMES_DASHBOARD_BASIC_AUTH_SECRET=<openssl rand -base64 32>
      environmentFiles = [ "/var/lib/hermes-secrets/env" ];

      # Web dashboard (sessions, cron, kanban) on the tailnet only: the firewall trusts just
      # tailscale0. Bind by interface, not name: `steammachine` resolves to 127.0.0.2 locally.
      backend = {
        mode = "dashboard";
        waitFor = "interface";
        interfaceName = "tailscale0";
      };

      # Every turn resends history; short replies keep it small.
      hermesHomeFiles."SOUL.md" = ''
        You are Leonard, siigna's assistant. Be terse: short sentences, no filler, no
        pleasantries, no recap of what was asked. Keep technical detail exact. Ask only
        when blocked.
      '';
    };
  };
}
