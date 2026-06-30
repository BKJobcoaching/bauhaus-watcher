# Bauhaus Verfügbarkeits-Watcher (PC-Version)
# Prüft die Produktseite von DEINER Privat-IP (kommt an Bauhaus' Cloudflare vorbei)
# und schickt bei Verfügbarkeit eine ntfy-Push aufs Handy.
# Nutzt das in Windows eingebaute curl.exe (der .NET-Abruf wird von Cloudflare geblockt).
# Wird von der Windows-Aufgabenplanung alle paar Minuten aufgerufen.

# ===================== EINSTELLUNGEN =====================
$NtfyTopic   = "HIER-DEIN-TOPIC"   # <-- dein geheimes ntfy-Topic eintragen!
$ProductUrl  = "https://www.bauhaus.info/klimaanlagen/midea-klimasplitgeraet-portasplit/p/31934233"
$ProductName = "Midea Klimasplitgeraet PortaSplit"
$NtfyServer  = "https://ntfy.sh"
# ========================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$StateFile = Join-Path $ScriptDir "state.json"
$LogFile   = Join-Path $ScriptDir "watch.log"
$UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

function Log($msg) {
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

if ($NtfyTopic -eq "HIER-DEIN-TOPIC") {
    Log "ABBRUCH: Bitte zuerst `$NtfyTopic oben im Skript eintragen."
    exit 1
}

# --- Seite via curl.exe laden (Body + HTTP-Status) ---
$out = & curl.exe -s --max-time 40 -A $UA -H "Accept-Language: de-DE,de;q=0.9" `
        -w "`nHTTPSTATUS:%{http_code}" $ProductUrl 2>$null
$body = ($out -join "`n")
$code = "000"
$cm = [regex]::Match($body, 'HTTPSTATUS:(\d+)\s*$')
if ($cm.Success) { $code = $cm.Groups[1].Value; $body = $body.Substring(0, $cm.Index) }

if ($code -ne "200") {
    Log "Abruf nicht erfolgreich (HTTP $code) - uebersprungen."
    exit 0
}
if ($body -match "Sicherheitspr|Just a moment|Attention Required") {
    Log "CAPTCHA-/Challenge-Seite erhalten - uebersprungen."
    exit 0
}

# --- Verfügbarkeit aus JSON-LD ---
$availRaw = $null
$m = [regex]::Match($body, '"availability"\s*:\s*"([^"]+)"', "IgnoreCase")
if ($m.Success) { $availRaw = $m.Groups[1].Value }

$price = $null
$pm = [regex]::Match($body, '"price"\s*:\s*"?([0-9.,]+)', "IgnoreCase")
if ($pm.Success) { $price = $pm.Groups[1].Value }

if (-not $availRaw) {
    Log "Kein availability-Feld gefunden (Seitenstruktur anders?) - uebersprungen."
    exit 0
}

$available = ($availRaw -match "InStock|LimitedAvailability|PreOrder|InStoreOnly") `
             -and ($availRaw -notmatch "OutOfStock|SoldOut|Discontinued")

# --- vorherigen Zustand lesen ---
$prev = $false
if (Test-Path $StateFile) {
    try { $prev = [bool](Get-Content $StateFile -Raw | ConvertFrom-Json).available } catch { $prev = $false }
}

Log "availability=$availRaw -> verfuegbar=$available (vorher=$prev, Preis=$price)"

# --- Push bei Flanke ausverkauft -> verfuegbar ---
if ($available -and -not $prev) {
    Log "WIEDER VERFUEGBAR - sende ntfy-Push"
    $msg = "$ProductName ist bei Bauhaus wieder verfuegbar"
    if ($price) { $msg += " ($price EUR)" }
    $msg += ". Jetzt zugreifen!"
    & curl.exe -s -H "Title: Wieder bestellbar!" -H "Priority: high" `
        -H "Tags: tada,shopping_cart" -H "Click: $ProductUrl" `
        -d $msg "$NtfyServer/$NtfyTopic" | Out-Null
    Log "Push gesendet."
}

# --- State speichern ---
@{ available = [bool]$available; lastChange = (Get-Date).ToUniversalTime().ToString("o") } |
    ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8
