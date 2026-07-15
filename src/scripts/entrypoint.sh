#!/usr/bin/env bash
##############################################################################
# Container entrypoint. Runs as root (PID 1 under tini):
#   1) ensures persistent directories (volumes) exist and are owned correctly,
#   2) drops privileges to user 'agent' and keeps the container alive.
# Users connect via `docker compose exec -u agent ...` or tmux.
##############################################################################
set -euo pipefail

AGENT_HOME=/home/agent

# Directories mounted as persistent volumes – freshly created volumes are
# owned by root, so we create them here and hand them to the agent user.
PERSIST_DIRS=(
  .codex .claude .config .cache
  .hermes .openclaw .agent2telegram .agentsmon
  .local .local/state .ssh
  workspace
)

for d in "${PERSIST_DIRS[@]}"; do
  mkdir -p "$AGENT_HOME/$d"
done

chown -R agent:agent "$AGENT_HOME" 2>/dev/null || true
chmod 700 "$AGENT_HOME/.ssh" 2>/dev/null || true

# Welcome message shown on interactive login
cat > "$AGENT_HOME/.motd" <<'MOTD'
────────────────────────────────────────────────────────────
 EvilAgent – multi-agent runtime (container = sandbox)
 Available: codex, claude, agy, hermes, openclaw,
            agent2telegram, agentsmon, voice2text
 Persistent data: ~/.codex ~/.claude ~/.config ~/workspace
 Start an agent in tmux:  tmux new -s master
────────────────────────────────────────────────────────────
MOTD
chown agent:agent "$AGENT_HOME/.motd" 2>/dev/null || true
grep -q 'cat ~/.motd' "$AGENT_HOME/.bashrc" 2>/dev/null || \
  echo '[ -f ~/.motd ] && cat ~/.motd' >> "$AGENT_HOME/.bashrc"

if [ "${1:-keepalive}" = "keepalive" ]; then
  # Start the shared tmux server (for agents) and keep the container alive.
  exec runuser -u agent -- bash -lc \
    'tmux start-server 2>/dev/null; tmux has-session -t main 2>/dev/null || tmux new-session -d -s main; exec sleep infinity'
else
  # Alternatively, run the provided command as agent.
  exec runuser -u agent -- bash -lc "$*"
fi
