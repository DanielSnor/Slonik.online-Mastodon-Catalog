#!/usr/bin/env bash
# Týdenní obnova instancí v JEDNOM kroku — vyřeší dvoufázovou závislost kategorií,
# takže i čerstvě přidaná instance dostane „Oblast" hned (ne až další týden):
#   1) build-instances --no-upload → web/instances.json se seznamem hostů + popisy
#                                     (lokálně; podklad pro classify, BEZ uploadu)
#   2) classify-instances          → zaměření do cache (joinmastodon + AI i pro NOVÉ)
#   3) build-instances             → zapeče kategorie do instances.json + upload
#
# classify nesmí shodit upload: když selže (např. bez AI klíče), pokračujeme a
# nahrajeme instance s tím, co už je v cache.
#
# Použití:  ./refresh-instances.sh        (cron: pondělí po update_catalog)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p logs
# Z cronu (bez terminálu) loguj do souboru; ruční běh píše na obrazovku.
# Přesměrování zdědí i volané build-instances.sh/classify-instances.sh → vše v instances.log.
[ -t 1 ] || exec >> "logs/instances.log" 2>&1

echo "── 1/3 build-instances (lokálně, bez uploadu) ──"
./build-instances.sh --no-upload

echo "── 2/3 classify-instances (zaměření do cache) ──"
./classify-instances.sh || echo "⚠️  classify selhalo — pokračuji s kategoriemi z cache"

echo "── 3/3 build-instances (zapéct kategorie + upload) ──"
./build-instances.sh
