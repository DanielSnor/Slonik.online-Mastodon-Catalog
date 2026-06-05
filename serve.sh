#!/usr/bin/env bash
# Lokální náhled webu (web/). Použití: ./serve.sh [port]   (default 8765)
set -euo pipefail
cd "$(dirname "$0")"
exec ruby bin/serve.rb "${1:-8765}" web
