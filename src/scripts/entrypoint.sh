#!/usr/bin/env bash
##############################################################################
# Container entrypoint. Runs as root (PID 1 under tini):
#   1) ensures persistent directories (volumes) exist and are owned correctly,
#   2) starts cron, so tools that keep themselves alive via a crontab work,
#   3) drops privileges to user 'agent' and keeps the container alive.
# Users connect via `docker compose exec -u agent ...` or tmux.
#
# Starting and restarting agents is NOT this script's job - that is what
# AgentsMonitor (`agentsmon service`) uses cron for. See README.md.
##############################################################################
set -euo pipefail

AGENT_HOME=/home/agent
AGENT_UID=1000
AGENT_GID=1000

# Directories mounted as persistent volumes - freshly created volumes are
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

# Only chown what is actually wrong. A blanket `chown -R` on every start walks
# the whole cache volume (multi-GB Whisper models) and the entire workspace,
# making startup time grow with your data.
for d in "${PERSIST_DIRS[@]}"; do
  path="$AGENT_HOME/$d"
  owner=$(stat -c '%u' "$path" 2>/dev/null || echo "")
  if [ "$owner" != "$AGENT_UID" ]; then
    echo "[entrypoint] fixing ownership of ~/$d (first use of this volume)"
    chown -R "$AGENT_UID:$AGENT_GID" "$path" 2>/dev/null || true
  fi
done
chown "$AGENT_UID:$AGENT_GID" "$AGENT_HOME" 2>/dev/null || true
chmod 700 "$AGENT_HOME/.ssh" 2>/dev/null || true

# Welcome message shown on interactive login
cat > "$AGENT_HOME/.motd" <<'MOTD'
────────────────────────────────────────────────────────────
 EvilAgent – multi-agent runtime (container = sandbox)
 Available: codex, claude, agy, hermes, openclaw,
            agent2telegram, agentsmon, voice2text
 Persistent data: ~/.codex ~/.claude ~/.config ~/workspace
 Tool inventory:  evilagent-health
 Keep agents alive 24/7:  agentsmon setup   (then: agentsmon status)
 Shared tmux session:     tmux attach -t main
────────────────────────────────────────────────────────────
MOTD
chown "$AGENT_UID:$AGENT_GID" "$AGENT_HOME/.motd" 2>/dev/null || true
grep -q 'cat ~/.motd' "$AGENT_HOME/.bashrc" 2>/dev/null || \
  echo '[ -f ~/.motd ] && cat ~/.motd' >> "$AGENT_HOME/.bashrc"

# Start cron while we are still root. This is what makes 24/7 operation work:
# `agentsmon service` installs an @reboot + every-minute crontab, so agents come
# back after a restart and get relaunched when they crash. Cron runs @reboot
# jobs when the daemon starts, which in a container means every container start.
if command -v cron >/dev/null 2>&1; then
  # The spool lives on a volume: it is outside $HOME, so without this a rebuild
  # would silently drop every cron job and agents would quietly stop starting.
  # Cron refuses to use the directory unless it is root:crontab 1730, and a
  # fresh volume arrives as root:root 0755.
  CRON_SPOOL=/var/spool/cron/crontabs
  mkdir -p "$CRON_SPOOL"
  chown root:crontab "$CRON_SPOOL" 2>/dev/null || true
  chmod 1730 "$CRON_SPOOL" 2>/dev/null || true
  cron && echo "[entrypoint] cron started"
fi

if [ "${1:-keepalive}" = "keepalive" ]; then
  # Start the shared tmux server (for agents) and keep the container alive.
  exec runuser -u agent -- bash -lc \
    'tmux start-server 2>/dev/null; tmux has-session -t main 2>/dev/null || tmux new-session -d -s main; exec sleep infinity'
else
  # Alternatively, run the provided command as agent.
  exec runuser -u agent -- bash -lc "$*"
fi
