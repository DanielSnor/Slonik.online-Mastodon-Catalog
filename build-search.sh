#!/usr/bin/env bash
# Build vyhledávacího indexu (build_search.rb) → web/search.json + web/users.json,
# upload na Surfer. Přírůstkově (denní cron); plný build přes --rebuild.
#
# Použití:
#   ./build-search.sh                 # přírůstkově + upload (denní cron)
#   ./build-search.sh --rebuild       # plný build od nuly
#   ./build-search.sh --no-catalog --no-upload
#   ./build-search.sh --bg [args…]    # běh na pozadí → logs/search.log (+ .pid)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p logs
# Z cronu (bez terminálu, bez --bg) loguj do souboru; ruční běh píše na obrazovku.
# --bg se spouští z terminálu (TTY), takže guard přeskočí a použije se nohup níže.
[ -t 1 ] || [ "${1:-}" = "--bg" ] || exec >> "logs/search.log" 2>&1

if [ "${1:-}" = "--bg" ]; then
  shift
  mkdir -p logs
  if command -v setsid >/dev/null 2>&1; then RUNNER="setsid nohup"; else RUNNER="nohup"; fi
  # shellcheck disable=SC2086
  $RUNNER ruby bin/build_search.rb "$@" > logs/search.log 2>&1 < /dev/null &
  echo $! > logs/search.pid
  echo "běží na pozadí (PID $(cat logs/search.pid)) → logs/search.log"
  echo "sleduj:  tail -f logs/search.log"
  exit 0
fi

exec ruby bin/build_search.rb "$@"
