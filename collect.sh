#!/usr/bin/env bash
# Denní sběr postů → data/posts_YYYY_Www.jsonl
# Použití: ./collect.sh [args…]   (např. DATE_OVERRIDE=2026-06-01 ./collect.sh)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p logs
# Z cronu (bez terminálu) loguj do souboru; ruční běh píše na obrazovku.
[ -t 1 ] || exec >> "logs/collect.log" 2>&1
exec ruby bin/collect_posts.rb "$@"
