#!/usr/bin/env bash
# Klasifikace zaměření instancí (classify_instances.rb) → data/instance_topics.json.
# joinmastodon primárně, AI fallback (klíč z ~/.anthropic_key). Pak spusť build-instances.sh.
#
# Použití:
#   ./classify-instances.sh             # joinmastodon + AI pro nové/změněné popisy
#   ./classify-instances.sh --dry-run   # nic nezapíše, jen ukáže, co by udělalo
#   ./classify-instances.sh --rebuild   # přepočítej i to, co je v cache
set -euo pipefail
cd "$(dirname "$0")"

# ANTHROPIC_API_KEY z ~/.anthropic_key, pokud není v prostředí.
if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -f "$HOME/.anthropic_key" ]; then
  export ANTHROPIC_API_KEY="$(cat "$HOME/.anthropic_key")"
fi

exec ruby bin/classify_instances.rb "$@"
