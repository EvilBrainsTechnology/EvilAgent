#!/usr/bin/env bash
##############################################################################
# Update EvilAgent. Data in volumes is left untouched.
#   1) backup,
#   2) rebuild image (new system packages + tools from install-tools.sh),
#   3) restart,
#   4) optionally refresh tools inside the running container.
##############################################################################
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 1/4 Backing up data"
./scripts/backup.sh || echo "   (backup skipped)"

echo "==> 2/4 Rebuilding image (--pull = latest base + tools)"
docker compose build --pull

echo "==> 3/4 Restarting with new image (volumes preserved)"
docker compose up -d

echo "==> 4/4 Refreshing CLI tools inside the container"
docker compose exec -u root evilagent \
  /usr/local/lib/evilagent/install-tools.sh || echo "   (skipped)"

echo "Done. Tool credentials remain intact."
