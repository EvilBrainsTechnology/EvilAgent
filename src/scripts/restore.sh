#!/usr/bin/env bash
##############################################################################
# Restore agent data from a backup created by scripts/backup.sh.
#
# Usage:  ./scripts/restore.sh <path to agent-data.tar.gz>
#         Both absolute and relative paths work; relative paths are resolved
#         against the directory you run the command from, not against src/.
##############################################################################
set -euo pipefail

ARCHIVE_ARG="${1:?Usage: restore.sh <path to agent-data.tar.gz>}"

# Resolve to an absolute path BEFORE cd'ing, so a path relative to the caller's
# working directory keeps working.
if [ ! -f "$ARCHIVE_ARG" ]; then
  echo "File not found: $ARCHIVE_ARG" >&2
  exit 1
fi
ARCHIVE_DIR=$(cd "$(dirname "$ARCHIVE_ARG")" && pwd)
ARCHIVE_FILE=$(basename "$ARCHIVE_ARG")

cd "$(dirname "$0")/.."

CONTAINER="${CONTAINER_NAME:-evilagent}"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "Container '$CONTAINER' is not running - start it with 'docker compose up -d'." >&2
  exit 1
fi

# Refuse to restore from an archive we cannot read.
if ! tar tzf "$ARCHIVE_DIR/$ARCHIVE_FILE" >/dev/null 2>&1; then
  echo "Archive is corrupt or unreadable: $ARCHIVE_DIR/$ARCHIVE_FILE" >&2
  exit 1
fi

echo "WARNING: this will overwrite current data in container $CONTAINER with"
echo "         $ARCHIVE_DIR/$ARCHIVE_FILE"
read -r -p "Continue? [yes/NO] " ans
[ "$ans" = "yes" ] || { echo "Aborted."; exit 0; }

docker run --rm \
  --volumes-from "$CONTAINER" \
  -v "$ARCHIVE_DIR:/backup:ro" \
  alpine sh -c "set -eu; cd /home/agent && tar xzf '/backup/$ARCHIVE_FILE'"

echo "Restored. Restarting container to apply correct ownership."
docker compose restart
