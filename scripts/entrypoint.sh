#!/usr/bin/env bash
##############################################################################
# Entrypoint kontejneru. Běží jako root (PID 1 pod tini):
#   1) zajistí existenci a vlastnictví trvalých adresářů (volumes),
#   2) zahodí práva na uživatele 'agent' a udrží kontejner naživu.
# Uživatel se pak připojuje přes `docker compose exec -u agent ...` / tmux.
##############################################################################
set -euo pipefail

AGENT_HOME=/home/agent

# Adresáře, které se montují jako trvalé volumes – po vytvoření jsou root:root,
# proto je vytvoříme a předáme agentovi.
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

# Uvítací nápověda pro interaktivní přihlášení
cat > "$AGENT_HOME/.motd" <<'MOTD'
────────────────────────────────────────────────────────────
 EvilAgent – běhové prostředí agentů (kontejner = sandbox)
 Dostupné: codex, claude, agy, hermes, openclaw,
           agent2telegram, agentsmon, voice2text
 Trvalá data: ~/.codex ~/.claude ~/.config ~/workspace ...
 Spuštění agenta v tmuxu:  tmux new -s master
────────────────────────────────────────────────────────────
MOTD
chown agent:agent "$AGENT_HOME/.motd" 2>/dev/null || true
grep -q 'cat ~/.motd' "$AGENT_HOME/.bashrc" 2>/dev/null || \
  echo '[ -f ~/.motd ] && cat ~/.motd' >> "$AGENT_HOME/.bashrc"

if [ "${1:-keepalive}" = "keepalive" ]; then
  # Nastartuj sdílený tmux server (pro agenty) a drž kontejner naživu.
  exec runuser -u agent -- bash -lc \
    'tmux start-server 2>/dev/null; tmux has-session -t main 2>/dev/null || tmux new-session -d -s main; exec sleep infinity'
else
  # Alternativně spusť předaný příkaz jako agent.
  exec runuser -u agent -- bash -lc "$*"
fi
