# Registriert den Bauhaus-Watcher als Windows-Aufgabe (alle 10 Minuten).
# Einmal ausführen (Rechtsklick -> "Mit PowerShell ausführen" oder im Terminal).
# Zum Entfernen:  Unregister-ScheduledTask -TaskName "BauhausWatcher" -Confirm:$false

$TaskName = "BauhausWatcher"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Watcher = Join-Path $ScriptDir "watch-bauhaus.ps1"

if (-not (Test-Path $Watcher)) { Write-Error "watch-bauhaus.ps1 nicht gefunden neben dieser Datei."; exit 1 }

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Watcher`""

# alle 10 Minuten, unbegrenzt, ab jetzt
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration ([TimeSpan]::MaxValue)

$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
    -DontStopOnIdleEnd -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 3)

# Im Kontext des aktuellen Nutzers, nur wenn angemeldet (kein Passwort nötig)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force `
    -Description "Prueft alle 10 Min ob der Bauhaus-Artikel wieder bestellbar ist und pusht via ntfy."

Write-Host ""
Write-Host "Aufgabe '$TaskName' eingerichtet - laeuft alle 10 Minuten." -ForegroundColor Green
Write-Host "Erster Lauf jetzt zum Test..."
Start-ScheduledTask -TaskName $TaskName
Write-Host "Fertig. Log siehst du in:  $(Join-Path $ScriptDir 'watch.log')"
