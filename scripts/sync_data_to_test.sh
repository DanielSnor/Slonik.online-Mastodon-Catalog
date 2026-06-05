#!/usr/bin/env bash
# ============================================================
# Sloník: Sync Data Prod → Test (na serveru)
# ============================================================
# Zkopíruje POUZE datové soubory z PROD do TEST instance NA SERVERU (rsync běží
# lokálně na serveru přes SSH) — ať test pracuje nad reálnými daty z produkce:
#   data/                 (stav/cache: collect_state, search_state,
#                          metrics_snapshot, instance_topics, discovered…)
#   web/*.json            (data.json, posts.json, search.json, users.json,
#                          instances.json, status.json)
# NEpřenáší kód, config.env ani config/ — jen data. Bez --delete.
#
# ⚠️ Přepíše datové soubory v TESTU verzí z produkce (test data jsou
#    znovuobnovitelná dávkovými skripty).
#
# Cesty: SLONIK_PROD_DIR (prod) → SLONIK_REMOTE_DIR (test) z scripts/deploy.env.
#
# Použití:
#   ./scripts/sync_data_to_test.sh --dry-run   # náhled (nic nezmění)
#   ./scripts/sync_data_to_test.sh             # zkopíruje data prod → test
# ============================================================
set -euo pipefail

LOCAL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$LOCAL_DIR/scripts/deploy.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "Chybí $ENV_FILE — zkopíruj scripts/deploy.env.example a vyplň SSH souřadnice."
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

REMOTE="${SLONIK_REMOTE:?SLONIK_REMOTE není v deploy.env}"
PORT="${SLONIK_REMOTE_PORT:-}"
TEST_DIR="${SLONIK_REMOTE_DIR:?SLONIK_REMOTE_DIR není v deploy.env}"
PROD_DIR="${SLONIK_PROD_DIR:?SLONIK_PROD_DIR není v deploy.env}"
RSYNC_PATH="${SLONIK_RSYNC_PATH:-rsync}"
EXTRA_SSH="${SLONIK_SSH_OPTS:-}"

DRY=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY="--dry-run" ;;
    *) echo "neznámý argument: $a"; exit 1 ;;
  esac
done

CTRL="/tmp/slonik-d2t-$$"
PORT_OPT=""; [ -n "$PORT" ] && PORT_OPT="-p $PORT"
SSH_OPTS="$PORT_OPT $EXTRA_SSH -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
-o ControlMaster=auto -o ControlPath=$CTRL -o ControlPersist=120"
ssh $SSH_OPTS "$REMOTE" true 2>/dev/null || true
trap 'ssh -O exit -o ControlPath=$CTRL "$REMOTE" 2>/dev/null; true' EXIT

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
[ -n "$DRY" ] && echo -e "${YELLOW}=== DRY-RUN (nic se nezmění) ===${NC}\n"

echo "============================================================"
echo -e "  ${CYAN}Data (na serveru): $PROD_DIR → $TEST_DIR${NC}"
echo "============================================================"
echo ""

# 1) data/ (stav + cache). rsync běží lokálně na serveru. Bez --delete.
echo -e "${CYAN}== data/ ==${NC}"
# shellcheck disable=SC2029
ssh $SSH_OPTS "$REMOTE" "$RSYNC_PATH -av $DRY --exclude='.DS_Store' \
  '$PROD_DIR/data/' '$TEST_DIR/data/'"
echo ""

# 2) web/*.json (publikovaná data: catalog/posts/search/users/instances/status)
echo -e "${CYAN}== web/*.json ==${NC}"
# shellcheck disable=SC2029
ssh $SSH_OPTS "$REMOTE" "$RSYNC_PATH -av $DRY \
  --include='*.json' --exclude='*' \
  '$PROD_DIR/web/' '$TEST_DIR/web/'"
echo ""

echo "============================================================"
if [ -n "$DRY" ]; then
  echo -e "${YELLOW}=== DRY-RUN — žádné změny ===${NC}"
else
  echo -e "${GREEN}=== Data prod → test zkopírována ===${NC}"
fi
echo -e "Přeneseno: ${CYAN}data/ + web/*.json${NC}  (kód a config beze změny)"
