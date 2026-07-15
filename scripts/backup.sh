#!/usr/bin/env bash
##############################################################################
# Záloha všech trvalých dat agentů do jednoho .tar.gz.
# Čte data přímo z běžícího kontejneru (--volumes-from), takže funguje
# bez ohledu na názvy volumes.
#
# Obnova:  ./scripts/restore.sh backups/<časové_razítko>/agent-data.tar.gz
##############################################################################
set -euo pipefail
cd "$(dirname "$0")/.."

CONTAINER=evilagent
TS=$(date +%Y%m%d-%H%M%S)
OUT="backups/$TS"
mkdir -p "$OUT"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "Kontejner '$CONTAINER' neběží – spusťte 'docker compose up -d'." >&2
  exit 1
fi

echo "Zálohuji data z kontejneru $CONTAINER ..."
docker run --rm \
  --volumes-from "$CONTAINER" \
  -v "$(pwd)/$OUT:/backup" \
  alpine sh -c 'cd /home/agent && tar czf /backup/agent-data.tar.gz \
    .codex .claude .config .cache .local/state \
    .hermes .openclaw .agent2telegram .agentsmon .ssh workspace 2>/dev/null || true'

echo "Hotovo: $OUT/agent-data.tar.gz"
ls -lh "$OUT/agent-data.tar.gz"
