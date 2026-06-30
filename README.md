# Bauhaus Verfügbarkeits-Watcher

Schickt dir eine **Push-Benachrichtigung aufs Handy**, sobald ein bestimmter
Bauhaus-Artikel wieder bestellbar ist. Läuft komplett kostenlos in **GitHub
Actions** (kein eigener Server) und pusht über **[ntfy.sh](https://ntfy.sh)**.

Beobachtet aktuell: **Midea Klimasplitgerät PortaSplit**
<https://www.bauhaus.info/klimaanlagen/midea-klimasplitgeraet-portasplit/p/31934233>

## So funktioniert's

1. GitHub Actions ruft alle ~10 Min `check.sh` auf.
2. Das Skript lädt die Produktseite (mit Browser-User-Agent, sonst HTTP 403)
   und liest das `availability`-Feld aus dem JSON-LD der Seite.
3. Wechselt der Status von *OutOfStock* → *InStock*, geht **einmalig** eine
   Push an dein ntfy-Topic. `state.json` merkt sich den Zustand, damit du nicht
   bei jedem Lauf erneut benachrichtigt wirst.

---

## Einrichtung (einmalig, ~5 Minuten)

### 1. ntfy-App einrichten
1. App **„ntfy"** installieren (Android/iOS) oder <https://ntfy.sh> im Browser öffnen.
2. Ein **Topic** abonnieren – wähle einen langen, schwer zu erratenden Namen,
   z. B. `bauhaus-midea-9f3k2x` (jeder, der den Namen kennt, kann mitlesen/senden).

### 2. Repository auf GitHub anlegen
1. Neues (privates) Repo erstellen, z. B. `bauhaus-watcher`.
2. Diesen Ordner hochladen / pushen:
   ```bash
   git init
   git add .
   git commit -m "Bauhaus Watcher"
   git branch -M main
   git remote add origin https://github.com/<dein-user>/bauhaus-watcher.git
   git push -u origin main
   ```

### 3. Topic & URL hinterlegen
Im Repo unter **Settings → Secrets and variables → Actions**:

**Secret** (Tab „Secrets"):
| Name | Wert |
|------|------|
| `NTFY_TOPIC` | dein Topic-Name, z. B. `bauhaus-midea-9f3k2x` |

**Variables** (Tab „Variables"):
| Name | Wert |
|------|------|
| `PRODUCT_URL` | `https://www.bauhaus.info/klimaanlagen/midea-klimasplitgeraet-portasplit/p/31934233` |
| `PRODUCT_NAME` | `Midea Klimasplitgerät PortaSplit` |
| `NTFY_SERVER` | `https://ntfy.sh` *(nur falls du einen eigenen ntfy-Server nutzt; sonst weglassen)* |

### 4. Testen
- Repo → **Actions** → Workflow „Bauhaus Verfügbarkeit prüfen" → **Run workflow**.
- Im Log siehst du `HTTP-Status: 200` und die erkannte Verfügbarkeit.
- Push-Test: kurz `state.json` auf `"available": true` setzen ist **nicht** nötig –
  willst du die ntfy-Zustellung testen, sende einmal manuell:
  ```bash
  curl -d "Testnachricht" ntfy.sh/<dein-topic>
  ```

Fertig. Ab jetzt bekommst du automatisch eine Push, sobald der Artikel
wieder bestellbar ist.

---

## Anderen Artikel beobachten
Einfach die Variable `PRODUCT_URL` (und `PRODUCT_NAME`) im Repo ändern – kein
Code-Update nötig. Funktioniert mit jeder Bauhaus-Produktseite, die JSON-LD
mit `availability` ausliefert (das ist Standard bei Bauhaus).

## Hinweise / Grenzen
- **Intervall:** GitHub-Cron ist nicht sekundengenau; `*/10` läuft real meist
  alle 10–15 Min. Für „so schnell wie möglich" kannst du auf `*/5` stellen,
  GitHub drosselt aber bei Last.
- **Bot-Block:** Sollte Bauhaus die GitHub-Server-IPs blocken (HTTP 403),
  überspringt der Lauf sauber und meldet eine Warning. Bisher kommt der
  Browser-User-Agent durch.
- **Datenschutz:** Wähle ein nicht erratbares ntfy-Topic. Wer den Namen kennt,
  kann Nachrichten an dieses Topic lesen und senden.
