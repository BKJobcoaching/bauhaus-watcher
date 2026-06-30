#!/usr/bin/env bash
# Prüft die OBI-Produktseite (direkt, ohne Scraper – OBI blockt keine Cloud-IPs)
# und schickt bei Online-Bestellbarkeit eine ntfy-Push.
# "online bestellbar" = JSON-LD availability InStock/PreOrder (NICHT InStoreOnly = nur Markt).
# state.json merkt sich den Zustand, damit nur bei der Flanke benachrichtigt wird.
set -euo pipefail

: "${PRODUCT_URL:?PRODUCT_URL fehlt}"
: "${NTFY_TOPIC:?NTFY_TOPIC fehlt}"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
PRODUCT_NAME="${PRODUCT_NAME:-OBI-Artikel}"

UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'

# --- Seite laden ---
http_code=$(curl -sS -o page.html -w '%{http_code}' \
  -A "$UA" \
  -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
  -H 'Accept-Language: de-DE,de;q=0.9' \
  "$PRODUCT_URL" || echo "000")

echo "HTTP-Status: $http_code  (Seitengröße: $(wc -c < page.html) Bytes)"

if [ "$http_code" != "200" ]; then
  echo "::warning::Abruf nicht erfolgreich (HTTP $http_code). Überspringe diesen Lauf."
  exit 0
fi

# --- Verfügbarkeit aus JSON-LD lesen ---
avail_raw=$(grep -oiE '"availability"[[:space:]]*:[[:space:]]*"[^"]*"' page.html | head -1 || true)
price=$(grep -oiE '"price"[[:space:]]*:[[:space:]]*"?[0-9.,]+' page.html | head -1 | grep -oE '[0-9.,]+' || true)

echo "availability roh: ${avail_raw:-<keins gefunden>}"
echo "preis: ${price:-?} EUR"

if [ -z "$avail_raw" ]; then
  echo "::warning::Kein availability-Feld gefunden. Überspringe."
  exit 0
fi

# online bestellbar = InStock/LimitedAvailability/PreOrder
# NICHT bestellbar  = OutOfStock, SoldOut, Discontinued, InStoreOnly (nur Markt)
available=false
if echo "$avail_raw" | grep -qiE 'InStock|LimitedAvailability|PreOrder' \
   && ! echo "$avail_raw" | grep -qiE 'OutOfStock|SoldOut|Discontinued|InStoreOnly'; then
  available=true
fi

# --- vorherigen Zustand lesen ---
prev=false
if [ -f state.json ]; then
  grep -qiE '"available"[[:space:]]*:[[:space:]]*true' state.json && prev=true || prev=false
fi
echo "Zustand vorher: $prev  →  jetzt: $available"

# --- Push bei Flanke nicht-bestellbar -> bestellbar ---
if [ "$available" = "true" ] && [ "$prev" != "true" ]; then
  echo "🎉 Online bestellbar – sende ntfy-Push an Topic '$NTFY_TOPIC'"
  curl -sS \
    -H "Title: ✅ Online bestellbar!" \
    -H "Priority: high" \
    -H "Tags: tada,shopping_cart" \
    -H "Click: $PRODUCT_URL" \
    -d "$PRODUCT_NAME ist bei OBI online bestellbar${price:+ ($price €)}. Jetzt zugreifen!" \
    "$NTFY_SERVER/$NTFY_TOPIC" >/dev/null
  echo "Push gesendet."
fi

# --- State nur bei Änderung schreiben ---
if [ "$available" != "$prev" ]; then
  printf '{\n  "available": %s,\n  "lastChange": "%s"\n}\n' "$available" "$(date -u +%FT%TZ)" > state.json
  echo "STATE_CHANGED=true" >> "$GITHUB_OUTPUT"
else
  echo "STATE_CHANGED=false" >> "$GITHUB_OUTPUT"
fi

rm -f page.html
