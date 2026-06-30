#!/usr/bin/env bash
# Überwacht die Midea PortaSplit über bestell.bar (Redundanz zu braucheklima).
# Quelle: schema.org JSON-LD auf der Produktseite (Offer je Händler mit availability).
# Pusht via ntfy, sobald ein Händler von OutOfStock auf bestellbar wechselt.
# state-bb.txt merkt sich die zuletzt verfügbaren Händler -> nur Flanken werden gemeldet.
set -euo pipefail

: "${NTFY_TOPIC:?NTFY_TOPIC fehlt}"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
PAGE_URL="${BB_URL:-https://www.bestell.bar/p/MTpH/midea-portasplit}"
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'

# --- Seite laden ---
http_code=$(curl -sS -o bb.html -w '%{http_code}' -A "$UA" -H 'Accept-Language: de-DE,de;q=0.9' "$PAGE_URL" || echo "000")
echo "HTTP-Status: $http_code  (Größe: $(wc -c < bb.html) Bytes)"
if [ "$http_code" != "200" ]; then
  echo "::warning::Abruf nicht erfolgreich (HTTP $http_code). Überspringe."; exit 0
fi

# --- JSON-LD-Block mit dem Product herausziehen ---
block=$(awk 'BEGIN{RS="</script>"} /application\/ld\+json/ && /"@type":"Product"/ { sub(/.*application\/ld\+json[^>]*>/,""); print; exit }' bb.html)
if [ -z "$block" ] || ! printf '%s' "$block" | jq -e . >/dev/null 2>&1; then
  echo "::warning::Kein gültiges Product-JSON-LD gefunden. Überspringe."; exit 0
fi

# --- alle Offer-Objekte herausziehen:  seller <TAB> availability <TAB> url ---
printf '%s' "$block" | jq -r '
  [.. | objects | select((.["@type"]? // "") == "Offer")]
  | .[]
  | "\(.seller.name // "?")\t\(.availability // "")\t\(.url // "")"
' > offers.tsv

echo "--- Händler-Status ---"
awk -F'\t' '{st=($2 ~ /OutOfStock|SoldOut|Discontinued/)?"✗ ausverkauft":($2 ~ /InStock|LimitedAvailability|PreOrder/?"✓ bestellbar":"? "$2); printf "  %-10s %s\n",$1,st}' offers.tsv

# --- aktuell bestellbare Händler ---
awk -F'\t' '$2 ~ /InStock|LimitedAvailability|PreOrder/ && $2 !~ /OutOfStock|SoldOut|Discontinued/' offers.tsv | sort -u > cur.tsv

# --- vorherige Liste ---
touch state-bb.txt
prev=$(cat state-bb.txt)

# --- neu bestellbare Händler -> Push ---
while IFS=$'\t' read -r seller avail url; do
  [ -z "$seller" ] && continue
  if ! grep -qxF "$seller" <(printf '%s\n' "$prev"); then
    echo "🎉 NEU bestellbar bei: $seller"
    curl -sS \
      -H "Title: ✅ PortaSplit bestellbar – $seller" \
      -H "Priority: high" \
      -H "Tags: tada,shopping_cart" \
      ${url:+-H "Click: $url"} \
      -d "Midea PortaSplit ist bei $seller bestellbar! (Quelle: bestell.bar)" \
      "$NTFY_SERVER/$NTFY_TOPIC" >/dev/null
    echo "  Push gesendet."
  fi
done < cur.tsv

# --- Liste speichern, wenn geändert ---
awk -F'\t' '{print $1}' cur.tsv | sed '/^$/d' | sort -u > state-bb.new
if ! cmp -s state-bb.new state-bb.txt; then
  mv state-bb.new state-bb.txt
  echo "STATE_CHANGED=true" >> "$GITHUB_OUTPUT"
else
  rm -f state-bb.new
  echo "STATE_CHANGED=false" >> "$GITHUB_OUTPUT"
fi

rm -f bb.html offers.tsv cur.tsv
