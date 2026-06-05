#!/usr/bin/env bash
# ============================================================
# Sloník: Sync Local → Test
# ============================================================
# Bezpečně synchronizuje KÓD z Macu na test server (script server).
# NIKDY nepřepíše data ani tajemství — vynechává:
#   config.env, data/, web/data.json, web/posts.json, logs/, *.bak
#   a (defaultně) i config/*.txt (kurátorské seznamy — server může mít vlastní).
#
# Konfigurace: scripts/deploy.env (zkopíruj z scripts/deploy.env.example).
#
# Použití:
#   ./scripts/sync_local_to_test.sh --dry-run      # náhled (nic nezmění)
#   ./scripts/sync_local_to_test.sh                # synchronizace kódu
#   ./scripts/sync_local_to_test.sh --with-config  # i config/*.txt (seznamy) — pozor!
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
PORT="${SLONIK_REMOTE_PORT:-}"          # prázdné = ber z ~/.ssh/config (alias)
DIR="${SLONIK_REMOTE_DIR:?SLONIK_REMOTE_DIR není v deploy.env}"
RSYNC_PATH="${SLONIK_RSYNC_PATH:-rsync}"
EXTRA_SSH="${SLONIK_SSH_OPTS:-}"        # volitelné (např. -i ~/.ssh/id_ed25519)

# --- argumenty ---
DRY=""
WITH_CONFIG=0
for a in "$@"; do
  case "$a" in
    --dry-run)     DRY="--dry-run" ;;
    --with-config) WITH_CONFIG=1 ;;
    *) echo "neznámý argument: $a"; exit 1 ;;
  esac
done

# --- SSH master spojení (reuse pro všechny rsync volání) ---
# Klíč/certifikát se použije automaticky (ssh-agent / ~/.ssh/config) → bez hesla.
# Port přidáme jen když je zadaný; jinak se vezme z ~/.ssh/config (vč. aliasu).
CTRL="/tmp/slonik-sync-$$"
PORT_OPT=""; [ -n "$PORT" ] && PORT_OPT="-p $PORT"
SSH_OPTS="$PORT_OPT $EXTRA_SSH -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
-o ControlMaster=auto -o ControlPath=$CTRL -o ControlPersist=120"
ssh $SSH_OPTS "$REMOTE" true 2>/dev/null || true
trap 'ssh -O exit -o ControlPath=$CTRL "$REMOTE" 2>/dev/null; true' EXIT

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
[ -n "$DRY" ] && echo -e "${YELLOW}=== DRY-RUN (nic se nezmění) ===${NC}\n"

# rsync helper: BEZ --delete (nikdy nic na serveru nemaže).
rs() { rsync -avz $DRY --exclude='.DS_Store' --exclude='*.bak' \
       --rsync-path="$RSYNC_PATH" -e "ssh $SSH_OPTS" "$@"; }

echo "============================================================"
echo -e "  ${CYAN}Sync: $LOCAL_DIR → $REMOTE:$DIR${NC}"
echo "============================================================"
echo ""

# 1) bin/*.rb
echo -e "${CYAN}== bin/*.rb ==${NC}"
rs --include='*/' --include='*.rb' --exclude='*' "$LOCAL_DIR/bin/" "$REMOTE:$DIR/bin/"
echo ""

# 2) lib/*.rb
echo -e "${CYAN}== lib/*.rb ==${NC}"
rs --include='*/' --include='*.rb' --exclude='*' "$LOCAL_DIR/lib/" "$REMOTE:$DIR/lib/"
echo ""

# 3) root *.sh (convenience wrappery)
echo -e "${CYAN}== *.sh (root) ==${NC}"
rs --include='*.sh' --exclude='*' "$LOCAL_DIR/" "$REMOTE:$DIR/"
echo ""

# 4) scripts/*.sh (deploy.env se NEsynchronizuje — není *.sh)
echo -e "${CYAN}== scripts/*.sh ==${NC}"
rs --include='*.sh' --exclude='*' "$LOCAL_DIR/scripts/" "$REMOTE:$DIR/scripts/"
echo ""

# 5) web/ assety (HTML/JS/CSS/MD + VŠECHNY obrázky) — BEZ *.json (to jsou data serveru!)
echo -e "${CYAN}== web/ assety (vč. obrázků, bez *.json dat) ==${NC}"
rs --include='*.html' --include='*.js' --include='*.css' --include='*.md' \
   --include='*.png' --include='*.jpg' --include='*.jpeg' --include='*.svg' \
   --include='*.webp' --include='*.gif' --include='*.ico' --exclude='*' \
   "$LOCAL_DIR/web/" "$REMOTE:$DIR/web/"
echo ""

# 6) docs/
echo -e "${CYAN}== docs/ ==${NC}"
rs "$LOCAL_DIR/docs/" "$REMOTE:$DIR/docs/"
echo ""

# 7) samostatné soubory v rootu
echo -e "${CYAN}== README.md, .gitignore, config.env.example ==${NC}"
for f in README.md .gitignore config.env.example; do
  [ -f "$LOCAL_DIR/$f" ] && rs "$LOCAL_DIR/$f" "$REMOTE:$DIR/$f"
done
echo ""

# 8) config/*.txt — jen na výslovné přání (--with-config)
if [ "$WITH_CONFIG" = 1 ]; then
  echo -e "${YELLOW}== config/ (--with-config: instances/seeds/manual/blocklist/crontab) ==${NC}"
  rs --include='*.txt' --include='crontab.example' --exclude='*' \
     "$LOCAL_DIR/config/" "$REMOTE:$DIR/config/"
else
  echo -e "${YELLOW}== config/*.txt PŘESKOČENO ==${NC} (server má vlastní; vynuť přes --with-config)"
fi
echo ""

# --- shrnutí ---
echo "============================================================"
if [ -n "$DRY" ]; then
  echo -e "${YELLOW}=== DRY-RUN — žádné změny ===${NC}"
else
  echo -e "${GREEN}=== Synchronizace kódu dokončena ===${NC}"
fi
echo -e "Nedotčeno na serveru: ${CYAN}config.env, data/, web/data.json, web/posts.json, logs/${NC}"
