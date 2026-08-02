#!/usr/bin/env bash
# Týdenní řetěz (pondělí): consolidate → discover → update → refresh-instances.
# Vše SEKVENČNĚ v jednom běhu, ať pořadí i závislosti drží bez ohledu na délku
# jednotlivých kroků (žádné hádání mezer v cronu). Cron volá jen tohle.
#
# Logy: každý krok si píše do svého logs/<jméno>.log; sem (logs/weekly.log) jdou
# jen stavové značky. Selhání jednoho kroku NEzastaví zbytek (kroky jsou volně
# závislé — discover/update jedou i ze staršího vstupu).
#
# Pořadí je důležité: consolidate (po pondělním collectu) → discover (kandidáti)
# → update (katalog z kandidátů) → refresh-instances (přehled/Oblast z katalogu)
# → cache-images ÚPLNĚ NAKONEC: čte data.json i instances.json a zapisuje do nich
#   cesty ke zmenšeným kopiím, takže musí za oběma.
set -uo pipefail
cd "$(dirname "$0")"
mkdir -p logs
[ -t 1 ] || exec >> "logs/weekly.log" 2>&1

echo "════════ týdenní běh start $(date -u '+%F %T UTC') ════════"
for step in consolidate discover update refresh-instances cache-images; do
  echo "── $step ──"
  if "./$step.sh"; then
    echo "✅ $step hotovo"
  else
    echo "⚠️  $step selhal (exit $?) — pokračuji dál"
  fi
done
echo "════════ týdenní běh konec $(date -u '+%F %T UTC') ════════"
