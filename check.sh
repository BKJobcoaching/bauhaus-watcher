#!/usr/bin/env bash
# Prüft die Bauhaus-Produktseite über eine Scraping-API (Residential-IP + JS-Render),
# da Bauhaus Rechenzentrums-IPs per CAPTCHA blockt. Bei Verfügbarkeit -> ntfy-Push.
# State (verfügbar ja/nein) in state.json, damit nur bei der Flanke benachrichtigt wird.
set -euo pipefail

: "${PRODUCT_URL:?PRODUCT_URL fehlt}"
: "${NTFY_TOPIC:?NTFY_TOPIC fehlt}"
: "${SCRAPER_API_KEY:?SCRAPER_API_KEY fehlt}"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
PRODUCT_NAME="${PRODUCT_NAME:-Bauhaus-Artikel}"
SCRAPER_PROVIDER="${SCRAPER_PROVIDER:-scraperapi}"

# URL-encoden (jq ist auf GitHub-Runnern vorinstalliert)
ENC=$(jq -rn --arg u "$PRODUCT_URL" '$u|@uri')

# Abruf-URL je nach Anbieter zusammenbauen (umschaltbar via SCRAPER_PROVIDER)
case "$SCRAPER_PROVIDER" in
  scraperapi)
    # ultra_premium=true: Anti-Bot-Bypass für geschützte Domains (Bauhaus/Cloudflare).
    # render bewusst AUS – die availability steht im rohen HTML, spart Credits.
    FETCH="https://api.scraperapi.com/?api_key=${SCRAPER_API_KEY}&url=${ENC}&ultra_premium=true&country_code=de" ;;
  scrapingbee)
    FETCH="https://app.scrapingbee.com/api/v1/?api_key=${SCRAPER_API_KEY}&url=${ENC}&render_js=true&premium_proxy=true&country_code=de" ;;
  scrapingant)
    FETCH="https://api.scrapingant.com/v2/general?url=${ENC}&x-api-key=${SCRAPER_API_KEY}&proxy_country=DE&browser=true" ;;
  *)
    echo "::error::Unbekannter SCRAPER_PROVIDER '$SCRAPER_PROVIDER'"; exit 1 ;;
esac

echo "Anbieter: $SCRAPER_PROVIDER"

# --- Seite über die API laden ---
http_code=$(curl -sS -m 90 -o page.html -w '%{http_code}' "$FETCH" || echo "000")
echo "HTTP-Status: $http_code  (Seitengröße: $(wc -c < page.html) Bytes)"

if [ "$http_code" != "200" ]; then
  echo "::warning::API-Abruf nicht erfolgreich (HTTP $http_code). Auszug:"
  head -c 400 page.html; echo
  echo "Überspringe diesen Lauf."
  exit 0
fi

# CAPTCHA-Seite trotz API? -> dann hat der Abruf nicht funktioniert
if grep -qiE 'Sicherheitsprüfung ihrer Verbindung|Just a moment|Attention Required' page.html; then
  echo "::warning::Antwort ist eine CAPTCHA-/Challenge-Seite – Anbieter kam nicht durch. Überspringe."
  exit 0
fi

# --- Verfügbarkeit aus JSON-LD lesen ---
avail_raw=$(grep -oiE '"availability"[[:space:]]*:[[:space:]]*"[^"]*"' page.html | head -1 || true)
price=$(grep -oiE '"price"[[:space:]]*:[[:space:]]*"?[0-9.,]+' page.html | head -1 | grep -oE '[0-9.,]+' || true)

echo "availability roh: ${avail_raw:-<keins gefunden>}"
echo "preis: ${price:-?} EUR"

if [ -z "$avail_raw" ]; then
  echo "::warning::Kein availability-Feld gefunden – Seitenstruktur evtl. anders gerendert. Überspringe."
  exit 0
fi

available=false
if echo "$avail_raw" | grep -qiE 'InStock|LimitedAvailability|PreOrder|InStoreOnly' \
   && ! echo "$avail_raw" | grep -qiE 'OutOfStock|SoldOut|Discontinued'; then
  available=true
fi

# --- vorherigen Zustand lesen ---
prev=false
if [ -f state.json ]; then
  grep -qiE '"available"[[:space:]]*:[[:space:]]*true' state.json && prev=true || prev=false
fi
echo "Zustand vorher: $prev  →  jetzt: $available"

# --- Push bei Flanke ausverkauft -> verfügbar ---
if [ "$available" = "true" ] && [ "$prev" != "true" ]; then
  echo "🎉 Wieder verfügbar – sende ntfy-Push an Topic '$NTFY_TOPIC'"
  curl -sS \
    -H "Title: ✅ Wieder bestellbar!" \
    -H "Priority: high" \
    -H "Tags: tada,shopping_cart" \
    -H "Click: $PRODUCT_URL" \
    -d "$PRODUCT_NAME ist bei Bauhaus wieder verfügbar${price:+ ($price €)}. Jetzt zugreifen!" \
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
