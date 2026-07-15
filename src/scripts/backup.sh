#!/usr/bin/env bash
##############################################################################
# Back up important persistent agent data into a single .tar.gz.
# Briefly stops the service and reads its volumes directly (--volumes-from),
# so the archive is consistent and works regardless of host volume names.
#
# A backup that fails is reported as a FAILURE and the incomplete archive is
# removed. Never report success for an archive we could not verify - update.sh
# runs this immediately before a destructive rebuild.
#
# Restore:  ./scripts/restore.sh backups/<timestamp>/agent-data.tar.gz
##############################################################################
set -euo pipefail
cd "$(dirname "$0")/.."

SERVICE=evilagent
TS=$(date +%Y%m%d-%H%M%S)
OUT="backups/$TS"

CONTAINER=$(docker compose ps -q "$SERVICE")
if [ -z "$CONTAINER" ]; then
  echo "Service '$SERVICE' is not running - start it with 'docker compose up -d'." >&2
  exit 1
fi

mkdir -p "$OUT"
ARCHIVE="$OUT/agent-data.tar.gz"

# Paths are relative to /home/agent. Missing ones are tolerated (a tool may be
# disabled via INSTALL_*), but any other tar error fails the backup.
PATHS=(
  .codex .claude .config .local/state
  .hermes .openclaw .agent2telegram .agentsmon .ssh workspace
)

restart_service() {
  echo "Restarting service $SERVICE ..."
  docker compose start "$SERVICE" >/dev/null
}

echo "Stopping service $SERVICE for a consistent backup ..."
docker compose stop "$SERVICE" >/dev/null
trap restart_service EXIT

echo "Backing up persistent data ..."
if ! MSYS_NO_PATHCONV=1 docker run --rm \
      --entrypoint bash \
      --volumes-from "$CONTAINER" \
      --mount "type=bind,source=$(pwd)/$OUT,target=/backup" \
      evilagent:latest -c '
        set -eu
        cd /home/agent
        existing=""
        for p in "$@"; do
          [ -e "$p" ] && existing="$existing $p"
        done
        [ -n "$existing" ] || { echo "nothing to back up in /home/agent" >&2; exit 1; }
        # shellcheck disable=SC2086
        tar --numeric-owner -czf /backup/agent-data.tar.gz \
          -C /home/agent $existing \
          -C /var/spool/cron crontabs
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

trap - EXIT
restart_service

echo "Done: $ARCHIVE ($ENTRIES entries)"
ls -lh "$ARCHIVE"
