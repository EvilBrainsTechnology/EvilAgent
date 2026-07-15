#!/usr/bin/env bash
##############################################################################
# Install / update agent CLI tools.
#
# Called:
#   - automatically at image build time (as root),
#   - manually to update tools inside a running container:
#       docker compose exec -u root evilagent \
#           /usr/local/lib/evilagent/install-tools.sh
#
# Each step is BEST-EFFORT: if an installer or URL is unavailable, the
# build/update continues and the tool is simply marked as missing.
# Reliable tools (Codex, Claude Code) are installed via npm; the rest use
# the official install scripts from the webinar.
##############################################################################
set -uo pipefail

log()  { printf '\n\033[1;36m[install-tools]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install-tools][WARN]\033[0m %s\n' "$*" >&2; }

# Run a command as user 'agent' with the correct HOME/PATH.
# Tools that install to ~/.local/bin stay in the agent's home directory.
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
npm install -g @openai/codex@latest || warn "npm @openai/codex failed"
have codex || as_agent 'curl -fsSL https://chatgpt.com/codex/install.sh | sh' \
  || warn "Codex could not be installed"

# 2) Claude Code (Anthropic) --------------------------------------------------
log "Claude Code (@anthropic-ai/claude-code)"
npm install -g @anthropic-ai/claude-code@latest || warn "npm @anthropic-ai/claude-code failed"
have claude || as_agent 'curl -fsSL https://claude.ai/install.sh | bash' \
  || warn "Claude Code could not be installed"

# 3) Agent2Telegram (Petr Ludwig) – bridge between Codex and Telegram ---------
log "Agent2Telegram"
as_agent 'curl -fsSL https://raw.githubusercontent.com/petrludwig-collab/Agent2Telegram/main/install.sh | bash' \
  || warn "Agent2Telegram unavailable (check repo/URL)"

# 4) Hermes Agent (Nous Research) ---------------------------------------------
log "Hermes Agent"
as_agent 'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash' \
  || warn "Hermes Agent unavailable"

# 5) OpenClaw -----------------------------------------------------------------
log "OpenClaw"
as_agent 'curl -fsSL https://openclaw.ai/install.sh | bash' \
  || warn "OpenClaw unavailable"

# 6) AgentsMonitor / AgentsMonitoring (Petr Ludwig) – monitoring + auto-recovery
log "AgentsMonitor"
as_agent 'curl -fsSL https://raw.githubusercontent.com/petrludwig-collab/AgentsMonitoring/main/install.sh | bash' \
  || warn "AgentsMonitor unavailable (check repo/URL)"

# 7) Google Antigravity CLI (agy) ---------------------------------------------
log "Google Antigravity"
as_agent 'curl -fsSL https://antigravity.google/cli/install.sh | bash' \
  || warn "Antigravity CLI unavailable (subscription does not work on servers – use a Google Cloud project / API key)"

# --- Summary -----------------------------------------------------------------
log "Installed tools:"
for b in codex claude agy hermes openclaw agent2telegram agentsmon; do
  if have "$b"; then printf '  \033[1;32m✓\033[0m %s\n' "$b"
  else               printf '  \033[1;31m✗\033[0m %s (not installed)\n' "$b"; fi
done
if /opt/whisper-venv/bin/python -c 'import faster_whisper' 2>/dev/null; then
  printf '  \033[1;32m✓\033[0m whisper (faster-whisper) – command: voice2text\n'
fi
echo
