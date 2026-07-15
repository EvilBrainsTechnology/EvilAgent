#!/usr/bin/env bash
##############################################################################
# Restore agent data from a backup created by scripts/backup.sh.
# Usage:  ./scripts/restore.sh backups/<timestamp>/agent-data.tar.gz
##############################################################################
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHIVE="${1:?Usage: restore.sh <path to agent-data.tar.gz>}"
CONTAINER=evilagent

if [ ! -f "$ARCHIVE" ]; then echo "File not found: $ARCHIVE" >&2; exit 1; fi
if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "Container '$CONTAINER' is not running – start it with 'docker compose up -d'." >&2
  exit 1
fi

echo "WARNING: this will overwrite current data in container $CONTAINER with $ARCHIVE"
read -r -p "Continue? [yes/NO] " ans
[ "$ans" = "yes" ] || { echo "Aborted."; exit 0; }

docker run --rm \
  --volumes-from "$CONTAINER" \
  -v "$(pwd)/$(dirname "$ARCHIVE"):/backup" \
  alpine sh -c "cd /home/agent && tar xzf /backup/$(basename "$ARCHIVE")"

echo "Restored. Restarting container to apply correct ownership."
docker compose restart
