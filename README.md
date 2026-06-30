# OBI Verfügbarkeits-Watcher

Schickt eine **Push-Benachrichtigung aufs Handy**, sobald die **Midea PortaSplit
bei OBI online bestellbar** ist. Läuft 24/7 kostenlos in **GitHub Actions**
(kein Server, kein Scraper) und pusht über **[ntfy.sh](https://ntfy.sh)**.

Beobachtet: <https://www.obi.de/p/8620890/midea-mobile-split-klimaanlage-portasplit>

> **Warum OBI statt Bauhaus?** bauhaus.info blockt alle Rechenzentrums-IPs per
> Cloudflare-CAPTCHA (GitHub, Hosting, Proxys – alles getestet). OBI nicht –
> daher klappt hier der einfache, kostenlose Direktabruf aus der Cloud.

## Ablauf
1. GitHub Actions ruft alle ~10 Min `check.sh` auf.
2. Liest das `availability`-Feld aus dem JSON-LD der OBI-Seite.
3. Wechsel `InStoreOnly` (nur Markt) → `InStock` (online bestellbar) ⇒
   **einmalige** ntfy-Push. `state.json` verhindert Spam.

## Einrichtung
1. **ntfy-App** installieren, geheimes Topic abonnieren.
2. Repo-Secret setzen unter *Settings → Secrets and variables → Actions → Secrets*:
   | Name | Wert |
   |------|------|
   | `NTFY_TOPIC` | dein Topic, z. B. `bauhaus-midea-bk7k2x9` |
3. **Actions → „… prüfen" → Run workflow** zum Testen. Erfolgreich, wenn das Log
   `HTTP-Status: 200` und `availability roh: ...InStoreOnly` zeigt.

> Das früher angelegte Secret `SCRAPER_API_KEY` wird nicht mehr gebraucht
> (kann bleiben oder gelöscht werden). Auch der PC-Weg unter `PC-Watcher/`
> ist nur noch ein optionales Backup.

## Anderer Artikel
`PRODUCT_URL`/`PRODUCT_NAME` in `.github/workflows/check.yml` ändern.

## Dateien
| Datei | Zweck |
|------|------|
| `check.sh` | Abruf, Auswertung, ntfy-Push |
| `.github/workflows/check.yml` | 10-Min-Cron + manueller Testlauf |
| `state.json` | merkt sich „bestellbar ja/nein" |
| `PC-Watcher/` | optionaler PC-Weg (PowerShell + Aufgabenplanung) für Bauhaus |
