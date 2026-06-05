#!/usr/bin/env bash
# ============================================================
# Sloník: Sync Test → Prod (na serveru)
# ============================================================
# Promote aplikace z TEST do PROD instance NA SERVERU (rsync běží lokálně na
# serveru přes SSH). Přenese KÓD a web assety (vč. obrázků), ale NIKDY:
#   config.env, scripts/deploy.env, data/, logs/, web/*.json (data)
#   a (defaultně) ani config/ (kurátorské seznamy + crontab) — prod má vlastní.
# Bez --delete: soubory, které prod má a my je vynecháváme, zůstanou.
#
# Cesty: SLONIK_REMOTE_DIR (test) → SLONIK_PROD_DIR (prod) z scripts/deploy.env.
#
# Použití:
#   ./scripts/sync_test_to_prod.sh --dry-run      # náhled (nic nezmění)
#   ./scripts/sync_test_to_prod.sh                # promote kódu test → prod
#   ./scripts/sync_test_to_prod.sh --with-config  # i config/ (seznamy/crontab)
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
WITH_CONFIG=0
for a in "$@"; do
  case "$a" in
    --dry-run)     DRY="--dry-run" ;;
    --with-config) WITH_CONFIG=1 ;;
    *) echo "neznámý argument: $a"; exit 1 ;;
  esac
done

CTRL="/tmp/slonik-t2p-$$"
PORT_OPT=""; [ -n "$PORT" ] && PORT_OPT="-p $PORT"
SSH_OPTS="$PORT_OPT $EXTRA_SSH -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
-o ControlMaster=auto -o ControlPath=$CTRL -o ControlPersist=120"
ssh $SSH_OPTS "$REMOTE" true 2>/dev/null || true
trap 'ssh -O exit -o ControlPath=$CTRL "$REMOTE" 2>/dev/null; true' EXIT

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
[ -n "$DRY" ] && echo -e "${YELLOW}=== DRY-RUN (nic se nezmění) ===${NC}\n"

CONFIG_EXCLUDE="--exclude=config/"
[ "$WITH_CONFIG" = 1 ] && CONFIG_EXCLUDE=""

echo "============================================================"
echo -e "  ${CYAN}Promote (na serveru): $TEST_DIR → $PROD_DIR${NC}"
echo "============================================================"
[ "$WITH_CONFIG" = 1 ] \
  && echo -e "${YELLOW}config/ SE PŘENÁŠÍ (--with-config)${NC}" \
  || echo -e "config/ se NEpřenáší (prod má vlastní; vynuť --with-config)"
echo ""

# rsync běží LOKÁLNĚ na serveru (oba adresáře jsou tam). Bez --delete.
# Single-quoted vzory (web/*.json) zůstávají literální pro vzdálený shell.
# shellcheck disable=SC2029
ssh $SSH_OPTS "$REMOTE" "$RSYNC_PATH -av $DRY \
  --exclude='.DS_Store' --exclude='*.bak' --exclude='.git/' \
  --exclude='config.env' --exclude='scripts/deploy.env' \
  --exclude='data/' --exclude='logs/' --exclude='web/*.json' \
  $CONFIG_EXCLUDE \
  '$TEST_DIR/' '$PROD_DIR/'"

echo ""
echo "============================================================"
if [ -n "$DRY" ]; then
  echo -e "${YELLOW}=== DRY-RUN — žádné změny ===${NC}"
else
  echo -e "${GREEN}=== Promote test → prod dokončen ===${NC}"
fi
echo -e "Nedotčeno v prod: ${CYAN}config.env, config/, data/, web/*.json, logs/${NC}"
