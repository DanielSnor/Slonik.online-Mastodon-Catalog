#!/usr/bin/env bash
# Deploy webu z TEST serveru na Surfer (přes Files API, stejně jako upload JSON).
# Spouštěj na serveru, kde je config.env se SURFER_URL/SURFER_TOKEN.
#
# Použití:
#   ./deploy-web.sh             # celý bundle (frontend + data.json + posts.json)
#   ./deploy-web.sh --assets    # jen frontend (index.html, app.js, app.css, header.jpg)
#   ./deploy-web.sh --data      # jen data.json + posts.json
#   ./deploy-web.sh --dry-run   # náhled
set -euo pipefail
cd "$(dirname "$0")"
exec ruby bin/deploy_web.rb "$@"
