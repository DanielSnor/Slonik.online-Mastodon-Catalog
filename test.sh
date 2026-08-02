#!/usr/bin/env bash
# Testy (čisté funkce; bez sítě a bez produkčních dat).
# Použití:  ./test.sh            všechny
#           ./test.sh posts      jen test/test_posts.rb
set -euo pipefail
cd "$(dirname "$0")"
exec ruby bin/run_tests.rb "$@"
