#!/usr/bin/env bash
##############################################################################
# Obnova dat agentů ze zálohy vytvořené scripts/backup.sh.
# Použití:  ./scripts/restore.sh backups/<časové_razítko>/agent-data.tar.gz
##############################################################################
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHIVE="${1:?Použití: restore.sh <cesta k agent-data.tar.gz>}"
CONTAINER=evilagent

if [ ! -f "$ARCHIVE" ]; then echo "Soubor neexistuje: $ARCHIVE" >&2; exit 1; fi
if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "Kontejner '$CONTAINER' neběží – spusťte 'docker compose up -d'." >&2
  exit 1
fi

echo "POZOR: přepíše aktuální data v kontejneru $CONTAINER daty z $ARCHIVE"
read -r -p "Pokračovat? [ano/NE] " ans
[ "$ans" = "ano" ] || { echo "Zrušeno."; exit 0; }

docker run --rm \
  --volumes-from "$CONTAINER" \
  -v "$(pwd)/$(dirname "$ARCHIVE"):/backup" \
  alpine sh -c "cd /home/agent && tar xzf /backup/$(basename "$ARCHIVE")"

echo "Obnoveno. Restartuji kontejner (kvůli právům/procesům)."
docker compose restart
