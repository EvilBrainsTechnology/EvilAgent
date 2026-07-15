#!/usr/bin/env bash
##############################################################################
# Back up all persistent agent data into a single .tar.gz.
# Reads data directly from the running container (--volumes-from), so it
# works regardless of the volume names on the host.
#
# A backup that fails is reported as a FAILURE and the incomplete archive is
# removed. Never report success for an archive we could not verify - update.sh
# runs this immediately before a destructive rebuild.
#
# Restore:  ./scripts/restore.sh backups/<timestamp>/agent-data.tar.gz
##############################################################################
set -euo pipefail
cd "$(dirname "$0")/.."

CONTAINER="${CONTAINER_NAME:-evilagent}"
TS=$(date +%Y%m%d-%H%M%S)
OUT="backups/$TS"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "Container '$CONTAINER' is not running - start it with 'docker compose up -d'." >&2
  exit 1
fi

mkdir -p "$OUT"
ARCHIVE="$OUT/agent-data.tar.gz"

# Paths are relative to /home/agent. Missing ones are tolerated (a tool may be
# disabled via INSTALL_*), but any other tar error fails the backup.
PATHS=(
  .codex .claude .config .cache .local/state
  .hermes .openclaw .agent2telegram .agentsmon .ssh workspace
)

echo "Backing up data from container $CONTAINER ..."
if ! docker run --rm \
      --volumes-from "$CONTAINER" \
      -v "$(pwd)/$OUT:/backup" \
      alpine sh -c '
        set -eu
        cd /home/agent
        existing=""
        for p in "$@"; do
          [ -e "$p" ] && existing="$existing $p"
        done
        [ -n "$existing" ] || { echo "nothing to back up in /home/agent" >&2; exit 1; }
        # shellcheck disable=SC2086
        tar czf /backup/agent-data.tar.gz $existing
      ' _ "${PATHS[@]}"; then
  echo "BACKUP FAILED - removing incomplete archive." >&2
  rm -f "$ARCHIVE"
  rmdir "$OUT" 2>/dev/null || true
  exit 1
fi

# Verify the archive is readable and non-empty before calling it a backup.
if ! tar tzf "$ARCHIVE" >/dev/null 2>&1; then
  echo "BACKUP FAILED - archive is corrupt or unreadable." >&2
  rm -f "$ARCHIVE"
  exit 1
fi

ENTRIES=$(tar tzf "$ARCHIVE" | wc -l)
if [ "$ENTRIES" -eq 0 ]; then
  echo "BACKUP FAILED - archive is empty." >&2
  rm -f "$ARCHIVE"
  exit 1
fi

echo "Done: $ARCHIVE ($ENTRIES entries)"
ls -lh "$ARCHIVE"
