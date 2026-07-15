#!/usr/bin/env bash
##############################################################################
# Back up all persistent agent data into a single .tar.gz.
# Reads data directly from the running container (--volumes-from), so it
# works regardless of the volume names on the host.
#
# Restore:  ./scripts/restore.sh backups/<timestamp>/agent-data.tar.gz
##############################################################################
set -euo pipefail
cd "$(dirname "$0")/.."

CONTAINER=evilagent
TS=$(date +%Y%m%d-%H%M%S)
OUT="backups/$TS"
mkdir -p "$OUT"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "Container '$CONTAINER' is not running – start it with 'docker compose up -d'." >&2
  exit 1
fi

echo "Backing up data from container $CONTAINER ..."
docker run --rm \
  --volumes-from "$CONTAINER" \
  -v "$(pwd)/$OUT:/backup" \
  alpine sh -c 'cd /home/agent && tar czf /backup/agent-data.tar.gz \
    .codex .claude .config .cache .local/state \
    .hermes .openclaw .agent2telegram .agentsmon .ssh workspace 2>/dev/null || true'

echo "Done: $OUT/agent-data.tar.gz"
ls -lh "$OUT/agent-data.tar.gz"
