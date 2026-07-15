#!/usr/bin/env bash
##############################################################################
# Container entrypoint. Runs as root (PID 1 under tini):
#   1) ensures persistent directories (volumes) exist and are owned correctly,
#   2) starts the shared tmux session and any configured autostart agents,
#   3) drops privileges to user 'agent' and keeps the container alive.
# Users connect via `docker compose exec -u agent ...` or tmux.
##############################################################################
set -euo pipefail

AGENT_HOME=/home/agent
AGENT_UID=1000
AGENT_GID=1000
LOG_DIR="$AGENT_HOME/.local/state/evilagent/logs"

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
mkdir -p "$LOG_DIR"

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
 Agent windows:   tmux attach -t main   (Ctrl+B W to list)
 Agent logs:      ~/.local/state/evilagent/logs/
────────────────────────────────────────────────────────────
MOTD
chown "$AGENT_UID:$AGENT_GID" "$AGENT_HOME/.motd" 2>/dev/null || true
grep -q 'cat ~/.motd' "$AGENT_HOME/.bashrc" 2>/dev/null || \
  echo '[ -f ~/.motd ] && cat ~/.motd' >> "$AGENT_HOME/.bashrc"

##############################################################################
# Autostart agents.
#
# Any AUTOSTART_<NAME>=<command> variable in .env becomes a tmux window named
# <name> running <command>. This is what makes 24/7 operation real: without it
# every agent has to be hand-started after each restart, reboot, or OOM kill,
# and the container comes back up healthy with nothing running inside it.
#
#   AUTOSTART_MASTER=codex --dangerously-bypass-approvals-and-sandbox
#   AUTOSTART_CLAUDE=claude --dangerously-skip-permissions
#
# Windows are created with remain-on-exit so a crashed agent leaves a visible
# dead window instead of silently disappearing - container-health reports it.
# Each window's output is piped to a log file as an audit trail.
##############################################################################
build_autostart_script() {
  local script=""
  local var name cmd log launch
  for var in $(compgen -e | sort); do
    case "$var" in
      AUTOSTART_*) ;;
      *) continue ;;
    esac
    cmd="${!var:-}"
    [ -n "$cmd" ] || continue

    name=$(echo "${var#AUTOSTART_}" | tr '[:upper:]_' '[:lower:]-')
    log="$LOG_DIR/$name.log"

    # The brief sleep lets pipe-pane attach before the agent writes anything.
    # Without it an agent that dies on startup - a bad config, a missing key,
    # exactly when you want the log - produces an empty log file.
    # `exec` then replaces the shell, so the agent keeps the pane's tty (TUIs
    # like codex/claude need one) and its real exit status reaches tmux.
    launch="sleep 0.3; exec $cmd"

    script+="tmux new-window -d -t main -n $(printf '%q' "$name") $(printf '%q' "sh -c $(printf '%q' "$launch")")"$'\n'
    script+="tmux pipe-pane -o -t main:$(printf '%q' "$name") $(printf '%q' "cat >> $log")"$'\n'
    script+="echo '[entrypoint] autostarted agent: $name'"$'\n'
  done
  printf '%s' "$script"
}

if [ "${1:-keepalive}" = "keepalive" ]; then
  AUTOSTART_SCRIPT=$(build_autostart_script)

  # Start the shared tmux server (for agents) and keep the container alive.
  exec runuser -u agent -- bash -lc "
    tmux start-server 2>/dev/null
    if ! tmux has-session -t main 2>/dev/null; then
      tmux new-session -d -s main -n shell
      # -gw = global WINDOW option. Without -g this would only apply to the
      # session's current window, and the agent windows created below would
      # silently disappear when they crash instead of being kept for inspection.
      tmux set-option -gw remain-on-exit on
      ${AUTOSTART_SCRIPT}
    fi
    exec sleep infinity
  "
else
  # Alternatively, run the provided command as agent.
  exec runuser -u agent -- bash -lc "$*"
fi
