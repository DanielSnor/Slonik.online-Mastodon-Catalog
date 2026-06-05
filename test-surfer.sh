#!/usr/bin/env bash
# Ověření přístupu na Surfer (POST/GET/DELETE přes Files API).
# Použití: ./test-surfer.sh [--keep]
set -euo pipefail
cd "$(dirname "$0")"
exec ruby bin/test_surfer.rb "$@"
