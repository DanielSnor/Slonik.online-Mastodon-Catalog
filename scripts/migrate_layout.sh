#!/usr/bin/env bash
# scripts/migrate_layout.sh
# ---------------------------------------------------------------------------
# Bezpečně převede STARÝ plochý layout Sloníka na nový:
#   bin/  lib/  config/  data/  docs/  web/  logs/
#
# Zachová veškerý stav serveru (katalog web/data.json, cache data/*, discovered).
# Idempotentní + NO-CLOBBER: nikdy nepřepíše ani nesmaže už existující soubor —
# jen varuje a nechá ho být. config.env se NEdotýká.
#
# Použití (v kořeni projektu na serveru):
#   bash scripts/migrate_layout.sh --dry-run   # jen ukáže, co by se přesunulo
#   bash scripts/migrate_layout.sh             # provede přesun
# ---------------------------------------------------------------------------
set -euo pipefail

# Kořen projektu = nadřazený adresář tohoto skriptu (scripts/..).
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

run() { if [ "$DRY" = 1 ]; then echo "  [dry] $*"; else eval "$*"; fi; }

echo "── Migrace layoutu ──"
echo "Kořen: $ROOT  | dry-run: $DRY"
echo

run "mkdir -p bin config data docs logs"

# Přesun s no-clobber: pokud cíl existuje, zdroj PONECHÁ a varuje (ručně vyřešit).
move() {  # move <dstdir> <src...>
  local dst="$1"; shift
  local f
  for f in "$@"; do
    [ -e "$f" ] || continue
    if [ -e "$dst/$(basename "$f")" ]; then
      echo "  ⚠️  $dst/$(basename "$f") UŽ EXISTUJE — '$f' ponechán (vyřeš ručně)"
    else
      run "mv \"$f\" \"$dst\"/"
      echo "  → $f → $dst/"
    fi
  done
}

# 1) web (site_test → web)
if [ -d site_test ] && [ ! -e web ]; then
  run "mv site_test web"
  echo "  → site_test/ → web/"
elif [ -e web ]; then
  echo "  = web/ už existuje — site_test/ (pokud je) ponechán"
else
  run "mkdir -p web"
  echo "  ⚠️  ani site_test/ ani web/ — vytvořen prázdný web/ (nahraj obsah!)"
fi

# 2) spustitelné skripty → bin/
move bin discover_accounts.rb update_catalog.rb collect_posts.rb \
         consolidate_posts.rb serve.rb test_surfer.rb ai_categorize.rb build_data.rb

# 3) kurátorské seznamy + crontab → config/
#    (po migraci je NEPŘEPISUJ deployem z devu — server má reálné zápisy)
move config instances.txt seeds.txt manual_accounts.txt blocklist.txt crontab.example

# 4) data / stav → data/
move data discovered_accounts.json skipped_noncz.json collect_state.json new_candidates.json
# shellcheck disable=SC2086
move data posts_*.jsonl

# 5) dokumentace → docs/
move docs ai_report.md

# 6) logy → logs/
move logs import.log import.pid run.log collect.log consolidate.log update.log

echo
echo "── Hotovo (dry-run=$DRY) ──"
echo "config.env i veškerá data zůstala nedotčena."
echo
echo "Další kroky:"
echo "  1) Nahraj NOVÝ kód z dev kopie (přepsat OK):"
echo "       bin/*.rb, lib/*.rb (vč. lib/paths.rb), *.sh, scripts/*.sh, README.md, .gitignore"
echo "     NEKOPÍRUJ z devu (stav serveru!):"
echo "       data/, web/data.json, web/posts.json, config.env, config/*.txt"
echo "  2) chmod +x *.sh scripts/*.sh"
echo "  3) Ověř:  ./update.sh --dry-run        (má ukázat tvůj plný katalog)"
echo "  4) Cron:  crontab config/crontab.example"
