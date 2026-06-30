<?php
// IP-Test: Kommt DIESER Server an Bauhaus vorbei (200) oder wird er geblockt (403/CAPTCHA)?
// 1) per FTP hochladen  2) im Browser aufrufen  3) Ergebnis Claude zeigen  4) Datei wieder löschen.
header('Content-Type: text/plain; charset=utf-8');

$url = 'https://www.bauhaus.info/klimaanlagen/midea-klimasplitgeraet-portasplit/p/31934233';
$ua  = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

if (!function_exists('curl_init')) {
    exit("cURL ist auf diesem Hosting nicht aktiv. Bitte Claude Bescheid geben.\n");
}

$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_TIMEOUT        => 30,
    CURLOPT_USERAGENT      => $ua,
    CURLOPT_HTTPHEADER     => ['Accept-Language: de-DE,de;q=0.9'],
]);
$body = (string) curl_exec($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$err  = curl_error($ch);
curl_close($ch);

echo "HTTP-Status: $code\n";
echo "cURL-Fehler: " . ($err ?: 'keiner') . "\n";
echo "Antwortgröße: " . strlen($body) . " Bytes\n\n";

$avail   = preg_match('/"availability"\s*:\s*"([^"]+)"/i', $body, $m) ? $m[1] : null;
$captcha = preg_match('/Sicherheitspr|Just a moment|CAPTCHA|captcha/i', $body);

if ($code === 200 && $avail) {
    echo "✅ ERFOLG: Dieser Server kommt durch!\n";
    echo "   Gefundene Verfügbarkeit: $avail\n";
    echo "   => FTP-Weg funktioniert. Sag Claude Bescheid.\n";
} elseif ($captcha || $code === 403) {
    echo "❌ GEBLOCKT: Bauhaus zeigt diesem Server eine Sicherheitsprüfung/CAPTCHA.\n";
    echo "   => FTP-Weg geht NICHT. Stattdessen PC- oder Scraping-API-Weg.\n";
} else {
    echo "⚠️ Unklar (HTTP $code). Schick Claude diese komplette Ausgabe.\n";
}
