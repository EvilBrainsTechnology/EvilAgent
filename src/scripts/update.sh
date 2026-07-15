#!/usr/bin/env bash
##############################################################################
# Update EvilAgent. Data in volumes is left untouched.
#   1) backup,
#   2) rebuild image (new system packages + tools from install-tools.sh),
#   3) restart with the new image.
#
# A failed backup ABORTS the update. Rebuilding on the strength of a backup
# that silently did not happen is how you lose credentials you cannot re-issue.
# Override with FORCE=1 if you genuinely want to proceed without one.
##############################################################################
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 1/3 Backing up data"
if ! ./scripts/backup.sh; then
  if [ "${FORCE:-0}" = "1" ]; then
    echo "   Backup FAILED - continuing anyway because FORCE=1." >&2
  else
    echo >&2
    echo "   Backup FAILED - aborting the update." >&2
    echo "   Fix the backup first, or re-run with FORCE=1 to update without one:" >&2
    echo "     FORCE=1 ./scripts/update.sh" >&2
    exit 1
  fi
fi

echo "==> 2/3 Rebuilding image (--pull = latest base + tools)"
docker compose build --pull

echo "==> 3/3 Restarting with new image (volumes preserved)"
docker compose up -d

echo "Done. Tool credentials remain intact."
