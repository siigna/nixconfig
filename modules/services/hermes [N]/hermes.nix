{ inputs, ... }:
{
  # Hermes Agent gateway: text the Telegram bot, the agent runs here (as the `hermes` user,
  # state in /var/lib/hermes) and replies. Model calls go to OpenRouter (Hermes' default).
  flake.modules.nixos.hermes = {
    imports = [ inputs.hermes-agent.nixosModules.default ];

    services.hermes-agent = {
      enable = true;
      settings.model.default = "anthropic/claude-sonnet-5.5";
      # Not in the repo (public) and not in the store. Create on the box, root:root 0600:
      #   OPENROUTER_API_KEY=...
      #   TELEGRAM_BOT_TOKEN=...
      #   TELEGRAM_ALLOWED_USERS=<numeric Telegram user id>   # gateway is default-deny without it
      environmentFiles = [ "/var/lib/hermes-secrets/env" ];
    };
  };
}
