#!/usr/bin/env bash
# ============================================================
# Sloník: Sync Test → Prod (na serveru)
# ============================================================
# Promote aplikace z TEST do PROD instance. Spouští se přímo na serveru
# (v kontejneru) — rsync běží lokálně bez SSH. Přenese KÓD a web assety
# (vč. obrázků), ale NIKDY:
#   config.env, scripts/deploy.env, data/, logs/, web/*.json (data)
#   a (defaultně) ani config/ (kurátorské seznamy + crontab) — prod má vlastní.
# Bez --delete: soubory, které prod má a my je vynecháváme, zůstanou.
#
# Použití:
#   ./scripts/sync_test_to_prod.sh --dry-run      # náhled (nic nezmění)
#   ./scripts/sync_test_to_prod.sh                # promote kódu test → prod
#   ./scripts/sync_test_to_prod.sh --with-config  # i config/ (seznamy/crontab)
# ============================================================
set -euo pipefail

TEST_DIR="/app/data/slonik-test"
PROD_DIR="/app/data/slonik"

DRY=""
WITH_CONFIG=0
for a in "$@"; do
  case "$a" in
    --dry-run)     DRY="--dry-run" ;;
    --with-config) WITH_CONFIG=1 ;;
    *) echo "neznámý argument: $a"; exit 1 ;;
  esac
done

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

rsync -av $DRY \
  --exclude='.DS_Store' --exclude='*.bak' --exclude='.git/' \
  --exclude='config.env' --exclude='scripts/deploy.env' \
  --exclude='data/' --exclude='logs/' --exclude='web/*.json' \
  $CONFIG_EXCLUDE \
  "$TEST_DIR/" "$PROD_DIR/"

echo ""
echo "============================================================"
if [ -n "$DRY" ]; then
  echo -e "${YELLOW}=== DRY-RUN — žádné změny ===${NC}"
else
  echo -e "${GREEN}=== Promote test → prod dokončen ===${NC}"
fi
echo -e "Nedotčeno v prod: ${CYAN}config.env, config/, data/, web/*.json, logs/${NC}"
