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

SERVICE=evilagent

CONTAINER=$(docker compose ps -q "$SERVICE")
if [ -z "$CONTAINER" ]; then
  echo "Service '$SERVICE' is not running - start it with 'docker compose up -d'." >&2
  exit 1
fi

# Refuse to restore from an archive we cannot read.
if ! tar tzf "$ARCHIVE_DIR/$ARCHIVE_FILE" >/dev/null 2>&1; then
  echo "Archive is corrupt or unreadable: $ARCHIVE_DIR/$ARCHIVE_FILE" >&2
  exit 1
fi
if tar tzf "$ARCHIVE_DIR/$ARCHIVE_FILE" \
  | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
  echo "Archive contains an unsafe path: $ARCHIVE_DIR/$ARCHIVE_FILE" >&2
  exit 1
fi

echo "WARNING: this will stop $SERVICE and overwrite its current data with"
echo "         $ARCHIVE_DIR/$ARCHIVE_FILE"
read -r -p "Continue? [yes/NO] " ans
[ "$ans" = "yes" ] || { echo "Aborted."; exit 0; }

docker compose stop "$SERVICE" >/dev/null

MSYS_NO_PATHCONV=1 docker run --rm \
  --entrypoint bash \
  --volumes-from "$CONTAINER" \
  --mount "type=bind,source=$ARCHIVE_DIR,target=/backup,readonly" \
  evilagent:latest -c '
    set -eu
    archive="$1"
    if tar tzf "$archive" | grep -q "^crontabs/"; then
      tar --numeric-owner -xzf "$archive" -C /home/agent --exclude=crontabs
      tar --numeric-owner -xzf "$archive" -C /var/spool/cron crontabs
    else
      # Backwards compatibility with archives created before crontabs were
      # included: every entry in those archives belongs under /home/agent.
      tar --numeric-owner -xzf "$archive" -C /home/agent
    fi
  ' _ "/backup/$ARCHIVE_FILE"

echo "Restored. Starting service to apply correct ownership."
docker compose start "$SERVICE" >/dev/null
