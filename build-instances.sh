#!/usr/bin/env bash
# Build přehledu instancí (build_instances.rb) → web/instances.json, upload na Surfer.
#
# Použití:
#   ./build-instances.sh              # build + upload (denní cron)
#   ./build-instances.sh --no-upload  # jen lokálně
set -euo pipefail
cd "$(dirname "$0")"
exec ruby bin/build_instances.rb "$@"
