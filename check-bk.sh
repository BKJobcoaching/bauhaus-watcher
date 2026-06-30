#!/usr/bin/env bash
# Überwacht die Midea PortaSplit über die JSON-API von braucheklima.de
# (aggregiert minutenaktuell Bauhaus/OBI/Toom/Hornbach/Hagebau/Globus/Amazon).
# Pusht via ntfy, sobald ein ONLINE-Händler den Artikel als bestellbar meldet.
# state-bk.txt merkt sich die zuletzt verfügbaren Händler -> nur Flanken werden gemeldet.
set -euo pipefail

: "${NTFY_TOPIC:?NTFY_TOPIC fehlt}"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
API_URL="${BK_API_URL:-https://braucheklima.de/api/availability}"
ARTICLE="${BK_ARTICLE:-Midea Portasplit}"
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'

# --- API laden ---
http_code=$(curl -sS -o avail.json -w '%{http_code}' -A "$UA" "$API_URL" || echo "000")
echo "HTTP-Status: $http_code  (Größe: $(wc -c < avail.json) Bytes)"
if [ "$http_code" != "200" ]; then
  echo "::warning::API-Abruf nicht erfolgreich (HTTP $http_code). Überspringe."
  exit 0
fi
if ! jq -e . avail.json >/dev/null 2>&1; then
  echo "::warning::Antwort ist kein valides JSON. Überspringe."
  exit 0
fi

# --- aktuell verfügbare Online-Händler ermitteln (neuester stock-Eintrag >= 1) ---
# Ausgabe je Zeile:  Händlername<TAB>URL
jq -r --arg art "$ARTICLE" '
  .[]
  | select(.plz == null)                          # nur Online-Händler (keine Filiale)
  | .name as $store
  | (.articles[$art]) as $a
  | select($a != null)
  | select((($a.stocks // [])[0].stock // 0) >= 1)
  | "\($store)\t\($a.url // "")"
' avail.json | sort -u > cur.tsv

echo "--- aktuell online bestellbar ---"
if [ -s cur.tsv ]; then cut -f1 cur.tsv | sed 's/^/  ✓ /'; else echo "  (keiner)"; fi

# --- vorherige Liste laden ---
touch state-bk.txt
prev_stores=$(cat state-bk.txt)
cur_stores=$(cut -f1 cur.tsv)

# --- neu hinzugekommene Händler = Flanke nicht-verfügbar -> verfügbar ---
changed=false
while IFS=$'\t' read -r store url; do
  [ -z "$store" ] && continue
  if ! grep -qxF "$store" <(printf '%s\n' "$prev_stores"); then
    echo "🎉 NEU online bestellbar bei: $store"
    changed=true
    curl -sS \
      -H "Title: ✅ PortaSplit bestellbar – $store" \
      -H "Priority: high" \
      -H "Tags: tada,shopping_cart" \
      ${url:+-H "Click: $url"} \
      -d "Midea PortaSplit ist bei $store online bestellbar! (Quelle: braucheklima.de)" \
      "$NTFY_SERVER/$NTFY_TOPIC" >/dev/null
    echo "  Push gesendet."
  fi
done < cur.tsv

# --- Liste speichern, wenn sie sich geändert hat ---
printf '%s\n' "$cur_stores" | sed '/^$/d' | sort -u > state-bk.new
if ! cmp -s state-bk.new state-bk.txt; then
  mv state-bk.new state-bk.txt
  echo "STATE_CHANGED=true" >> "$GITHUB_OUTPUT"
else
  rm -f state-bk.new
  echo "STATE_CHANGED=false" >> "$GITHUB_OUTPUT"
fi

rm -f avail.json cur.tsv
