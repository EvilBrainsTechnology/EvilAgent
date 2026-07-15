#!/usr/bin/env bash
##############################################################################
# Instalace / aktualizace agentních CLI nástrojů.
#
# Volá se:
#   - automaticky při buildu image (jako root),
#   - ručně pro aktualizaci nástrojů v běžícím kontejneru:
#       docker compose exec -u root evilagent \
#           /usr/local/lib/evilagent/install-tools.sh
#
# Každý krok je BEST-EFFORT: pokud je některý installer/URL nedostupný,
# build/aktualizace pokračuje dál a nástroj se jen označí jako chybějící.
# Spolehlivé nástroje (Codex, Claude Code) se instalují přes npm, ostatní
# přes oficiální instalační skripty z prezentace.
##############################################################################
set -uo pipefail

log()  { printf '\n\033[1;36m[install-tools]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install-tools][POZOR]\033[0m %s\n' "$*" >&2; }

# Spuštění příkazu jako uživatel 'agent' se správným HOME/PATH.
# Nástroje, které se instalují do ~/.local/bin, tak zůstávají v home agenta.
as_agent() {
  runuser -u agent -- env \
    HOME=/home/agent \
    PATH="/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    CODEX_HOME=/home/agent/.codex \
    CLAUDE_CONFIG_DIR=/home/agent/.claude \
    bash -lc "$1"
}

have() { as_agent "command -v $1 >/dev/null 2>&1"; }

# 1) Codex CLI (OpenAI) – meta-agent -----------------------------------------
log "Codex CLI (@openai/codex)"
npm install -g @openai/codex@latest || warn "npm @openai/codex selhal"
have codex || as_agent 'curl -fsSL https://chatgpt.com/codex/install.sh | sh' \
  || warn "Codex se nepodařilo nainstalovat"

# 2) Claude Code (Anthropic) --------------------------------------------------
log "Claude Code (@anthropic-ai/claude-code)"
npm install -g @anthropic-ai/claude-code@latest || warn "npm @anthropic-ai/claude-code selhal"
have claude || as_agent 'curl -fsSL https://claude.ai/install.sh | bash' \
  || warn "Claude Code se nepodařilo nainstalovat"

# 3) Agent2Telegram (Petr Ludwig) – most Codex <-> Telegram ------------------
log "Agent2Telegram"
as_agent 'curl -fsSL https://raw.githubusercontent.com/petrludwig-collab/Agent2Telegram/main/install.sh | bash' \
  || warn "Agent2Telegram nedostupný (ověřte repo/URL)"

# 4) Hermes Agent (Nous Research) --------------------------------------------
log "Hermes Agent"
as_agent 'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash' \
  || warn "Hermes Agent nedostupný"

# 5) OpenClaw -----------------------------------------------------------------
log "OpenClaw"
as_agent 'curl -fsSL https://openclaw.ai/install.sh | bash' \
  || warn "OpenClaw nedostupný"

# 6) AgentsMonitor / AgentsMonitoring (Petr Ludwig) – monitoring + obnova ----
log "AgentsMonitor"
as_agent 'curl -fsSL https://raw.githubusercontent.com/petrludwig-collab/AgentsMonitoring/main/install.sh | bash' \
  || warn "AgentsMonitor nedostupný (ověřte repo/URL)"

# 7) Google Antigravity CLI (agy) --------------------------------------------
log "Google Antigravity"
as_agent 'curl -fsSL https://antigravity.google/cli/install.sh | bash' \
  || warn "Antigravity CLI nedostupné (na serveru nejde přes předplatné – použijte Google Cloud projekt / API klíč)"

# --- Přehled -----------------------------------------------------------------
log "Přehled nainstalovaných nástrojů:"
for b in codex claude agy hermes openclaw agent2telegram agentsmon; do
  if have "$b"; then printf '  \033[1;32m✓\033[0m %s\n' "$b"
  else               printf '  \033[1;31m✗\033[0m %s (nenainstalováno)\n' "$b"; fi
done
if /opt/whisper-venv/bin/python -c 'import faster_whisper' 2>/dev/null; then
  printf '  \033[1;32m✓\033[0m whisper (faster-whisper) – příkaz: voice2text\n'
fi
echo
