#!/usr/bin/env bash
# Aktualizace katalogu (update_catalog.rb). API klíč se načte z ~/.anthropic_key.
#
# Použití:
#   ./update.sh --dry-run            # jen diff + odhad ceny
#   ./update.sh --no-categorize      # jen refresh (zdarma): aktivita, vyřazení botů
#   ./update.sh --retype             # přeznač type u aktivních
#   ./update.sh --refamily           # přeznač family u aktivních v koši „lifestyle"
#   ./update.sh                      # plná aktualizace + upload
#   ./update.sh --bg [args…]         # spustí na pozadí → logs/update.log (+ .pid)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p logs
# Z cronu (bez terminálu, bez --bg) loguj do souboru; ruční běh píše na obrazovku.
# --bg se spouští z terminálu (TTY), takže guard přeskočí a použije se nohup níže.
[ -t 1 ] || [ "${1:-}" = "--bg" ] || exec >> "logs/update.log" 2>&1

# ANTHROPIC_API_KEY z ~/.anthropic_key, pokud není v prostředí.
if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -f "$HOME/.anthropic_key" ]; then
  export ANTHROPIC_API_KEY="$(cat "$HOME/.anthropic_key")"
fi

# --bg → běh na pozadí (přežije odhlášení; crash-safe díky checkpointům).
if [ "${1:-}" = "--bg" ]; then
  shift
  mkdir -p logs
  if command -v setsid >/dev/null 2>&1; then RUNNER="setsid nohup"; else RUNNER="nohup"; fi
  # shellcheck disable=SC2086
  $RUNNER ruby bin/update_catalog.rb "$@" > logs/update.log 2>&1 < /dev/null &
  echo $! > logs/update.pid
  echo "běží na pozadí (PID $(cat logs/update.pid)) → logs/update.log"
  echo "sleduj:  tail -f logs/update.log"
  exit 0
fi

exec ruby bin/update_catalog.rb "$@"
