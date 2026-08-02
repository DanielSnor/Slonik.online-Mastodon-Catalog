#!/usr/bin/env bash
# Ověří, že otisky (integrity) externích skriptů v index.html pořád sedí.
# Když ne, prohlížeče je nespouštějí a měření návštěvnosti tiše stojí.
# Použití:  ./check-sri.sh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p logs
# Z cronu (bez terminálu) loguj do souboru; ruční běh píše na obrazovku.
[ -t 1 ] || exec >> "logs/sri.log" 2>&1
exec ruby bin/check_sri.rb "$@"
