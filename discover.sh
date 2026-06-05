#!/usr/bin/env bash
# Objevování účtů (seeds.txt + directory instances.txt) → data/discovered_accounts.json
# Použití: ./discover.sh [args…]   (např. MAX_PER_SEED=500 ./discover.sh)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p logs
# Z cronu (bez terminálu) loguj do souboru; ruční běh píše na obrazovku.
[ -t 1 ] || exec >> "logs/discover.log" 2>&1
exec ruby bin/discover_accounts.rb "$@"
