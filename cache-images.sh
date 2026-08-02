#!/usr/bin/env bash
# Lokální kopie obrázků z cizích serverů (avatary účtů + loga instancí),
# zmenšené a servírované z vlastní domény.
# Použití:
#   ./cache-images.sh               # doplní chybějící, prořeže, nahraje
#   ./cache-images.sh --dry-run     # jen spočítá
#   ./cache-images.sh --rebuild     # od nuly
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p logs
# Z cronu (bez terminálu) loguj do souboru; ruční běh píše na obrazovku.
[ -t 1 ] || exec >> "logs/images.log" 2>&1
exec ruby bin/cache_images.rb "$@"
