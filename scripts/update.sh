#!/usr/bin/env bash
##############################################################################
# Aktualizace EvilAgent. Data ve volumes zůstávají netknutá.
#   1) záloha,
#   2) rebuild image (nové verze systému + nástrojů z install-tools.sh),
#   3) restart,
#   4) volitelně refresh nástrojů uvnitř běžícího kontejneru.
##############################################################################
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 1/4 Záloha dat"
./scripts/backup.sh || echo "   (záloha přeskočena)"

echo "==> 2/4 Rebuild image (--pull = aktuální base + nástroje)"
docker compose build --pull

echo "==> 3/4 Restart s novým image (volumes zůstávají)"
docker compose up -d

echo "==> 4/4 Aktualizace CLI nástrojů uvnitř kontejneru"
docker compose exec -u root evilagent \
  /usr/local/lib/evilagent/install-tools.sh || echo "   (přeskočeno)"

echo "Hotovo. Přihlášení nástrojů zůstává zachováno."
