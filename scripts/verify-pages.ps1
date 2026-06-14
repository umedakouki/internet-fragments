param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')]
    [string]$Genre,
    [string]$BaseUrl = 'https://umedakouki.github.io/internet-fragments/'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $root 'output'
New-Item -ItemType Directory -Force -Path $output | Out-Null

function Get-FreePort { $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $listener.Start(); $port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port; $listener.Stop(); return $port }
$debugPort = Get-FreePort
$profile = Join-Path $output "pages-profile-$PID"
$browserExe = @('C:\Program Files\Google\Chrome\Application\chrome.exe','C:\Program Files (x86)\Google\Chrome\Application\chrome.exe','C:\Program Files\Microsoft\Edge\Application\msedge.exe','C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $browserExe) { throw 'Chrome or Edge was not found.' }

$index = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data/genres/index.json') | ConvertFrom-Json
$entry = @($index.genres | Where-Object { $_.id -eq $Genre }) | Select-Object -First 1
if (-not $entry) { throw "Genre not found: $Genre" }
$genreData = Get-Content -Raw -Encoding UTF8 (Join-Path $root $entry.path) | ConvertFrom-Json
$expectedCount = @($genreData.items).Count
$firstItemId = [string]$genreData.items[0].id
$legacy = $index.legacyCollections.PSObject.Properties | Where-Object { $_.Value -eq $Genre } | Select-Object -First 1
$browserProcess = $null; $socket = $null; $nextId = 0

function Send-Cdp([string]$method, [hashtable]$params = @{}) {
    $script:nextId++; $id = $script:nextId
    $bytes = [Text.Encoding]::UTF8.GetBytes((@{ id = $id; method = $method; params = $params } | ConvertTo-Json -Compress -Depth 20))
    $segment = New-Object ArraySegment[byte] -ArgumentList (, $bytes)
    $script:socket.SendAsync($segment, [Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null
    while ($true) {
        $stream = New-Object IO.MemoryStream
        do { $buffer = New-Object byte[] 65536; $receiveSegment = New-Object ArraySegment[byte] -ArgumentList (, $buffer); $result = $script:socket.ReceiveAsync($receiveSegment, [Threading.CancellationToken]::None).GetAwaiter().GetResult(); $stream.Write($buffer, 0, $result.Count) } while (-not $result.EndOfMessage)
        $message = [Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
        if ($message.id -eq $id) { if ($message.error) { throw ($message.error | ConvertTo-Json -Compress) }; return $message.result }
    }
}
function Invoke-Eval([string]$expression) { $response = Send-Cdp 'Runtime.evaluate' @{ expression = $expression; awaitPromise = $true; returnByValue = $true }; if ($response.exceptionDetails) { throw ($response.exceptionDetails | ConvertTo-Json -Compress -Depth 8) }; return $response.result.value }
function Wait-For([string]$expression) { for ($attempt = 0; $attempt -lt 100; $attempt++) { if (Invoke-Eval $expression) { return }; Start-Sleep -Milliseconds 250 }; throw "Timed out waiting for: $expression" }

try {
    $browserInfo = New-Object Diagnostics.ProcessStartInfo
    $browserInfo.FileName = $browserExe
    $browserInfo.Arguments = "--headless=new --disable-gpu --no-sandbox --no-first-run --no-default-browser-check --remote-debugging-port=$debugPort --user-data-dir=`"$profile`" --window-size=1440,1000 $BaseUrl"
    $browserInfo.UseShellExecute = $false; $browserInfo.CreateNoWindow = $true
    $browserProcess = [Diagnostics.Process]::Start($browserInfo)
    $page = $null
    for ($attempt = 0; $attempt -lt 40; $attempt++) { try { $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$debugPort/json" -TimeoutSec 2; $page = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1; if ($page) { break } } catch {}; Start-Sleep -Milliseconds 400 }
    if (-not $page) { throw 'Browser debugging endpoint was not available.' }
    $socket = New-Object Net.WebSockets.ClientWebSocket; $socket.ConnectAsync([Uri]$page.webSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null
    Send-Cdp 'Runtime.enable' | Out-Null; Send-Cdp 'Page.enable' | Out-Null

    Send-Cdp 'Page.navigate' @{ url = $BaseUrl } | Out-Null
    Wait-For "document.querySelectorAll('.genre-node').length>0"
    $public = Invoke-Eval "(async()=>{const root=new URL('$BaseUrl');const read=async path=>{const response=await fetch(new URL(path,root),{cache:'no-store'});return {status:response.status,text:await response.text()};};const indexResult=await read('data/genres/index.json');const genreResult=await read('$($entry.path)');const assetResponse=await fetch(new URL('$($entry.representativeAsset)',root),{cache:'no-store'});const assetBytes=(await assetResponse.arrayBuffer()).byteLength;const index=JSON.parse(indexResult.text);const genre=JSON.parse(genreResult.text);return {htmlStatus:performance.getEntriesByType('navigation')[0].responseStatus,title:document.title,indexStatus:indexResult.status,indexGenres:index.genres.length,indexCount:index.genres.find(x=>x.id==='$Genre').itemCount,genreStatus:genreResult.status,genreCount:genre.itemCount,genreItems:genre.items.length,assetStatus:assetResponse.status,assetType:assetResponse.headers.get('content-type'),assetBytes};})()"

    Send-Cdp 'Page.navigate' @{ url = "$BaseUrl`?genre=$Genre" } | Out-Null
    Wait-For "document.querySelector('#exploration-panel').dataset.state==='genre'"
    $directGenre = Invoke-Eval "({status:performance.getEntriesByType('navigation')[0].responseStatus,url:location.search,state:document.querySelector('#exploration-panel').dataset.state,genre:document.querySelector('#exploration-panel').dataset.genre,cards:document.querySelectorAll('.specimen-card').length})"

    Send-Cdp 'Page.navigate' @{ url = "$BaseUrl`?genre=$Genre&item=$firstItemId" } | Out-Null
    Wait-For "document.querySelector('#exploration-panel').dataset.state==='item' && document.querySelectorAll('#branch-options button').length===3"
    $directItem = Invoke-Eval "({status:performance.getEntriesByType('navigation')[0].responseStatus,url:location.search,state:document.querySelector('#exploration-panel').dataset.state,item:document.querySelector('#exploration-panel').dataset.item,branches:document.querySelectorAll('#branch-options button').length,source:document.querySelector('.source-button').href})"

    if ($legacy) {
        $legacyDate = [string]$legacy.Name
        Send-Cdp 'Page.navigate' @{ url = "$BaseUrl`?collection=$legacyDate" } | Out-Null
        Wait-For "location.search==='?genre=$Genre' && document.querySelector('#exploration-panel').dataset.state==='genre'"
        $legacyResult = Invoke-Eval "({status:performance.getEntriesByType('navigation')[0].responseStatus,url:location.search,state:document.querySelector('#exploration-panel').dataset.state})"
    } else { $legacyResult = $null }

    $failed = $public.htmlStatus -ne 200 -or $public.indexStatus -ne 200 -or $public.indexCount -ne $expectedCount -or $public.genreStatus -ne 200 -or $public.genreCount -ne $expectedCount -or $public.genreItems -ne $expectedCount -or $public.assetStatus -ne 200 -or -not $public.assetType.StartsWith('image/') -or $public.assetBytes -lt 1000
    $failed = $failed -or $directGenre.status -ne 200 -or $directGenre.url -ne "?genre=$Genre" -or $directGenre.state -ne 'genre' -or $directGenre.genre -ne $Genre -or $directGenre.cards -lt 1
    $failed = $failed -or $directItem.status -ne 200 -or $directItem.url -ne "?genre=$Genre&item=$firstItemId" -or $directItem.state -ne 'item' -or $directItem.item -ne $firstItemId -or $directItem.branches -ne 3 -or -not $directItem.source.StartsWith('http')
    if ($legacyResult -and ($legacyResult.status -ne 200 -or $legacyResult.url -ne "?genre=$Genre" -or $legacyResult.state -ne 'genre')) { $failed = $true }

    [pscustomobject]@{ public = $public; directGenre = $directGenre; directItem = $directItem; legacy = $legacyResult } | ConvertTo-Json -Depth 8
    if ($failed) { throw 'Published Pages verification failed.' }
    Write-Host "Published Pages verification passed for $Genre."
} finally {
    if ($socket) { try { $socket.Dispose() } catch {} }
    if ($browserProcess -and -not $browserProcess.HasExited) { try { $browserProcess.Kill() } catch {} }
    Start-Sleep -Milliseconds 250
    if (Test-Path -LiteralPath $profile) { $resolved = [IO.Path]::GetFullPath($profile); if ($resolved.StartsWith([IO.Path]::GetFullPath($output), [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue } }
}
