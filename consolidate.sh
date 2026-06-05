#!/usr/bin/env bash
# Týdenní konsolidace postů → web/posts.json → upload na Surfer
# Použití: ./consolidate.sh [args…]   (např. ./consolidate.sh --dry-run)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p logs
# Z cronu (bez terminálu) loguj do souboru; ruční běh píše na obrazovku.
[ -t 1 ] || exec >> "logs/consolidate.log" 2>&1
exec ruby bin/consolidate_posts.rb "$@"
