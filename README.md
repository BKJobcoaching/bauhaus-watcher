# Bauhaus Verfügbarkeits-Watcher

Schickt eine **Push-Benachrichtigung aufs Handy**, sobald ein bestimmter
Bauhaus-Artikel wieder bestellbar ist. Läuft 24/7 in **GitHub Actions**
(kein eigener Server) und pusht über **[ntfy.sh](https://ntfy.sh)**.

Beobachtet: **Midea Klimasplitgerät PortaSplit**
<https://www.bauhaus.info/klimaanlagen/midea-klimasplitgeraet-portasplit/p/31934233>

## Warum eine Scraping-API?

Bauhaus blockt Rechenzentrums-IPs (GitHub, Hosting, Proxys) mit einer
**Cloudflare-CAPTCHA-Prüfung** (HTTP 403). Nur „echte" Privat-/Residential-IPs
kommen durch. Der Watcher holt die Seite deshalb über eine **Scraping-API**
(z. B. ScraperAPI) mit Residential-IPs und JS-Rendering.

## Ablauf
1. GitHub Actions ruft alle 30 Min `check.sh` auf.
2. `check.sh` lädt die Produktseite über die Scraping-API und liest das
   `availability`-Feld aus dem JSON-LD.
3. Wechsel *OutOfStock → InStock* ⇒ **einmalige** ntfy-Push. `state.json`
   merkt sich den Zustand (kein Spam).

---

## Einrichtung

### 1. ntfy-App
- App **„ntfy"** installieren, ein **geheimes Topic** abonnieren
  (z. B. `bauhaus-midea-bk7k2x9`).

### 2. Scraping-API-Key besorgen
- Bei einem Anbieter kostenlos registrieren und den **API-Key** kopieren:
  - **ScraperAPI** – <https://www.scraperapi.com> (Standard, `render=true`)
  - Alternativen: ScrapingBee, ScrapingAnt (per `SCRAPER_PROVIDER` umschaltbar)

### 3. Secrets im Repo eintragen
**Settings → Secrets and variables → Actions → Tab „Secrets"**, zwei Stück:

| Name | Wert |
|------|------|
| `NTFY_TOPIC` | dein ntfy-Topic, z. B. `bauhaus-midea-bk7k2x9` |
| `SCRAPER_API_KEY` | dein API-Key vom Anbieter |

*(Optional, Tab „Variables": `SCRAPER_PROVIDER` = `scrapingbee` oder
`scrapingant`, falls du nicht ScraperAPI nutzt.)*

### 4. Testen
- **Actions → „Bauhaus Verfügbarkeit prüfen" → Run workflow**.
- Erfolgreich, wenn im Log steht: `HTTP-Status: 200` und
  `availability roh: ...OutOfStock`.
- ntfy-Zustellung separat testen: `curl -d "Test" ntfy.sh/<dein-topic>`.

---

## Hinweise / Grenzen
- **Gratis-Kontingente sind klein.** Cloudflare-Bypass kostet pro Abruf mehrere
  Credits; mit ~1000 Gratis-Credits/Monat ist alle 30 Min realistisch. Bei
  größerem Plan in `.github/workflows/check.yml` den Cron auf `*/10` stellen.
- **Falls der Anbieter nicht durchkommt:** Das Log zeigt „CAPTCHA-/Challenge-Seite".
  Dann Anbieter wechseln (`SCRAPER_PROVIDER`) oder Premium-/Stealth-Proxy des
  Anbieters aktivieren.
- **Anderer Artikel:** `PRODUCT_URL`/`PRODUCT_NAME` im Workflow ändern.
- **Datenschutz:** ntfy-Topic geheim halten – wer den Namen kennt, kann mitlesen.

## Dateien
| Datei | Zweck |
|------|------|
| `check.sh` | Abruf über Scraping-API, Auswertung, ntfy-Push |
| `.github/workflows/check.yml` | 30-Min-Cron + manueller Testlauf |
| `state.json` | merkt sich „verfügbar ja/nein" |
| `ftp-test/bauhaus-iptest.php` | Einmal-Test, ob ein Server durchkommt (nicht im Betrieb nötig) |
