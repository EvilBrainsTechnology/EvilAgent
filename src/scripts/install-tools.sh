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
# Tool selection: each tool is guarded by an INSTALL_<TOOL> env var
# (default: true). At build time these come from build args (.env ->
# docker-compose), at runtime from the container environment (env_file),
# so `make tools` respects the same .env configuration.
#
# Failure handling:
#   - Codex and Claude Code install via npm and are RELIABLE, so if one of them
#     is enabled and fails, the build fails - an image without the agent you
#     asked for is not a successful build.
#   - The webinar tools install via third-party scripts whose URLs are often
#     unavailable. Those are best-effort: they warn, the build continues, and
#     the tool shows as missing in `make health`.
##############################################################################
set -uo pipefail

log()  { printf '\n\033[1;36m[install-tools]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install-tools][WARN]\033[0m %s\n' "$*" >&2; }
skip() { printf '\033[1;90m[install-tools]\033[0m %s skipped (%s=false)\n' "$1" "$2"; }

REQUIRED_MISSING=()

# Is the tool enabled? Anything other than "false" (including unset) = enabled.
enabled() {
  local var="INSTALL_$1"
  [ "${!var:-true}" != "false" ]
}

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

# Download an install script to a file, then run it. Piping curl straight into a
# shell would execute a half-downloaded script if the connection drops midway.
#   fetch_and_run <label> <url> [interpreter]
fetch_and_run() {
  local label="$1" url="$2" interp="${3:-bash}" tmp rc

  tmp=$(mktemp /tmp/install-XXXXXX.sh)
  if ! curl -fsSL "$url" -o "$tmp"; then
    warn "$label: download failed ($url)"
    rm -f "$tmp"
    return 1
  fi
  if [ ! -s "$tmp" ]; then
    warn "$label: downloaded script is empty ($url)"
    rm -f "$tmp"
    return 1
  fi

  chown agent:agent "$tmp"
  chmod 0644 "$tmp"
  as_agent "$interp $tmp"
  rc=$?
  rm -f "$tmp"
  return $rc
}

# 1) Codex CLI (OpenAI) - meta-agent -----------------------------------------
if enabled CODEX; then
  log "Codex CLI (@openai/codex)"
  npm install -g @openai/codex@latest || warn "npm @openai/codex failed"
  have codex || fetch_and_run "Codex" "https://chatgpt.com/codex/install.sh" sh \
    || warn "Codex could not be installed"
  have codex || REQUIRED_MISSING+=("codex")
else
  skip "Codex" INSTALL_CODEX
fi

# 2) Claude Code (Anthropic) --------------------------------------------------
if enabled CLAUDE_CODE; then
  log "Claude Code (@anthropic-ai/claude-code)"
  npm install -g @anthropic-ai/claude-code@latest || warn "npm @anthropic-ai/claude-code failed"
  have claude || fetch_and_run "Claude Code" "https://claude.ai/install.sh" bash \
    || warn "Claude Code could not be installed"
  have claude || REQUIRED_MISSING+=("claude")
else
  skip "Claude Code" INSTALL_CLAUDE_CODE
fi

# --- Best-effort tools (third-party installers, URLs from the webinar) -------

# 3) Agent2Telegram (Petr Ludwig) - bridge between Codex and Telegram ---------
if enabled AGENT2TELEGRAM; then
  log "Agent2Telegram"
  fetch_and_run "Agent2Telegram" \
    "https://raw.githubusercontent.com/petrludwig-collab/Agent2Telegram/main/install.sh" \
    || warn "Agent2Telegram unavailable (check repo/URL)"
else
  skip "Agent2Telegram" INSTALL_AGENT2TELEGRAM
fi

# 4) Hermes Agent (Nous Research) ---------------------------------------------
if enabled HERMES; then
  log "Hermes Agent"
  fetch_and_run "Hermes Agent" "https://hermes-agent.nousresearch.com/install.sh" \
    || warn "Hermes Agent unavailable"
else
  skip "Hermes Agent" INSTALL_HERMES
fi

# 5) OpenClaw -----------------------------------------------------------------
if enabled OPENCLAW; then
  log "OpenClaw"
  fetch_and_run "OpenClaw" "https://openclaw.ai/install.sh" \
    || warn "OpenClaw unavailable"
else
  skip "OpenClaw" INSTALL_OPENCLAW
fi

# 6) AgentsMonitor / AgentsMonitoring (Petr Ludwig) - monitoring + auto-recovery
if enabled AGENTSMONITOR; then
  log "AgentsMonitor"
  fetch_and_run "AgentsMonitor" \
    "https://raw.githubusercontent.com/petrludwig-collab/AgentsMonitoring/main/install.sh" \
    || warn "AgentsMonitor unavailable (check repo/URL)"
else
  skip "AgentsMonitor" INSTALL_AGENTSMONITOR
fi

# 7) Google Antigravity CLI (agy) ---------------------------------------------
if enabled ANTIGRAVITY; then
  log "Google Antigravity"
  fetch_and_run "Google Antigravity" "https://antigravity.google/cli/install.sh" \
    || warn "Antigravity CLI unavailable (subscription does not work on servers - use a Google Cloud project / API key)"
else
  skip "Google Antigravity" INSTALL_ANTIGRAVITY
fi

# --- Summary -----------------------------------------------------------------
# Shared with `make health` so the two can never disagree.
log "Installed tools:"
/usr/local/bin/evilagent-health

if [ ${#REQUIRED_MISSING[@]} -gt 0 ]; then
  echo
  warn "Failed to install: ${REQUIRED_MISSING[*]}"
  warn "These install via npm and are expected to work - failing rather than"
  warn "producing an image without the agent you asked for. Set INSTALL_<TOOL>=false"
  warn "if you don't need it."
  exit 1
fi
echo
