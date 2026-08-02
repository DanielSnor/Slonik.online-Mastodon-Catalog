#!/usr/bin/env bash
# Lokální kopie avatarů katalogu (zmenšené, na vlastní doméně).
# Použití:
#   ./cache-avatars.sh              # doplní chybějící, prořeže, nahraje
#   ./cache-avatars.sh --dry-run    # jen spočítá
#   ./cache-avatars.sh --rebuild    # od nuly
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p logs
# Z cronu (bez terminálu) loguj do souboru; ruční běh píše na obrazovku.
[ -t 1 ] || exec >> "logs/avatars.log" 2>&1
exec ruby bin/cache_avatars.rb "$@"
