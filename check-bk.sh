#!/usr/bin/env bash
# Überwacht die Midea PortaSplit über die JSON-API von braucheklima.de.
# Meldet via ntfy:
#   - ONLINE-Bestellbarkeit (Bauhaus/OBI/Toom/Hornbach/Hagebau/Globus/Amazon)
#   - Verfügbarkeit in BERLINER Filialen (vor Ort)
# state-bk.txt merkt sich die zuletzt verfügbaren Standorte -> nur Flanken werden gemeldet.
set -euo pipefail

: "${NTFY_TOPIC:?NTFY_TOPIC fehlt}"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
API_URL="${BK_API_URL:-https://braucheklima.de/api/availability}"
ARTICLE="${BK_ARTICLE:-Midea Portasplit}"
CITY_RE="${BK_CITY_RE:-^Berlin}"   # welche Filialen-Städte zählen (Regex)
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'

# --- API laden ---
http_code=$(curl -sS -o avail.json -w '%{http_code}' -A "$UA" "$API_URL" || echo "000")
echo "HTTP-Status: $http_code  (Größe: $(wc -c < avail.json) Bytes)"
if [ "$http_code" != "200" ]; then
  echo "::warning::API-Abruf nicht erfolgreich (HTTP $http_code). Überspringe."; exit 0
fi
if ! jq -e . avail.json >/dev/null 2>&1; then
  echo "::warning::Antwort ist kein valides JSON. Überspringe."; exit 0
fi

# --- aktuell verfügbare Standorte ermitteln (neuester stock-Eintrag >= 1) ---
# Spalten:  typ <TAB> name <TAB> url <TAB> strasse <TAB> plz
jq -r --arg art "$ARTICLE" --arg city "$CITY_RE" '
  .[]
  | select(.plz == null or ((.city // "") | test($city)))   # Online ODER Zielstadt
  | . as $s
  | (.articles[$art]) as $a
  | select($a != null)
  | select((($a.stocks // [])[0].stock // 0) >= 1)
  | (if $s.plz == null then "online" else "filiale" end) as $typ
  | "\($typ)\t\($s.name)\t\($a.url // "")\t\($s.street // "")\t\($s.plz // "")"
' avail.json | sort -u > cur.tsv

echo "--- aktuell verfügbar ---"
if [ -s cur.tsv ]; then awk -F'\t' '{printf "  ✓ [%s] %s\n",$1,$2}' cur.tsv; else echo "  (keiner)"; fi

# --- vorherige Liste laden ---
touch state-bk.txt
prev=$(cat state-bk.txt)

# --- neu hinzugekommene Standorte = Flanke nicht-verfügbar -> verfügbar ---
while IFS=$'\t' read -r typ name url street plz; do
  [ -z "$name" ] && continue
  if ! grep -qxF "$name" <(printf '%s\n' "$prev"); then
    if [ "$typ" = "online" ]; then
      title="✅ PortaSplit bestellbar – $name"
      body="Midea PortaSplit ist bei $name online bestellbar! (Quelle: braucheklima.de)"
      tags="tada,shopping_cart"
    else
      title="📍 PortaSplit vor Ort – $name"
      body="Midea PortaSplit ist verfügbar in: $name${street:+, $street}${plz:+ $plz} (Quelle: braucheklima.de)"
      tags="round_pushpin,department_store"
    fi
    echo "🎉 NEU verfügbar: [$typ] $name"
    curl -sS \
      -H "Title: $title" \
      -H "Priority: high" \
      -H "Tags: $tags" \
      ${url:+-H "Click: $url"} \
      -d "$body" \
      "$NTFY_SERVER/$NTFY_TOPIC" >/dev/null
    echo "  Push gesendet."
  fi
done < cur.tsv

# --- Liste speichern, wenn geändert ---
awk -F'\t' '{print $2}' cur.tsv | sed '/^$/d' | sort -u > state-bk.new
if ! cmp -s state-bk.new state-bk.txt; then
  mv state-bk.new state-bk.txt
  echo "STATE_CHANGED=true" >> "$GITHUB_OUTPUT"
else
  rm -f state-bk.new
  echo "STATE_CHANGED=false" >> "$GITHUB_OUTPUT"
fi

rm -f avail.json cur.tsv
