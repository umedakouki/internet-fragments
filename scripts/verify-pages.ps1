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

function Get-FreePort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    $listener.Stop()
    return $port
}

$debugPort = Get-FreePort
$profile = Join-Path $output "pages-profile-$PID"
$browserExe = @(
    'C:\Program Files\Google\Chrome\Application\chrome.exe',
    'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $browserExe) { throw 'Chrome or Edge was not found.' }

$index = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data/genres/index.json') | ConvertFrom-Json
$entry = @($index.genres | Where-Object { $_.id -eq $Genre }) | Select-Object -First 1
if (-not $entry) { throw "Genre not found: $Genre" }
$genreData = Get-Content -Raw -Encoding UTF8 (Join-Path $root $entry.path) | ConvertFrom-Json
$expectedCount = @($genreData.items).Count
$legacy = $index.legacyCollections.PSObject.Properties | Where-Object { $_.Value -eq $Genre } | Select-Object -First 1
$browserProcess = $null
$socket = $null
$nextId = 0

function Send-Cdp([string]$method, [hashtable]$params = @{}) {
    $script:nextId++
    $id = $script:nextId
    $bytes = [Text.Encoding]::UTF8.GetBytes((@{ id = $id; method = $method; params = $params } | ConvertTo-Json -Compress -Depth 20))
    $segment = New-Object ArraySegment[byte] -ArgumentList (, $bytes)
    $script:socket.SendAsync($segment, [Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null
    while ($true) {
        $buffer = New-Object byte[] 1048576
        $received = $script:socket.ReceiveAsync((New-Object ArraySegment[byte] -ArgumentList (, $buffer)), [Threading.CancellationToken]::None).GetAwaiter().GetResult()
        $message = [Text.Encoding]::UTF8.GetString($buffer, 0, $received.Count) | ConvertFrom-Json
        if ($message.id -eq $id) { return $message }
    }
}

function Invoke-Eval([string]$expression) {
    $response = Send-Cdp 'Runtime.evaluate' @{ expression = $expression; awaitPromise = $true; returnByValue = $true }
    if ($response.result.exceptionDetails) { throw $response.result.exceptionDetails.text }
    return $response.result.result.value
}

function Wait-For([string]$expression) {
    for ($i = 0; $i -lt 100; $i++) {
        if (Invoke-Eval $expression) { return }
        Start-Sleep -Milliseconds 100
    }
    throw "Timed out waiting for: $expression"
}

try {
    $browserInfo = New-Object Diagnostics.ProcessStartInfo
    $browserInfo.FileName = $browserExe
    $browserInfo.Arguments = "--headless=new --disable-gpu --no-sandbox --no-first-run --no-default-browser-check --remote-debugging-port=$debugPort --user-data-dir=`"$profile`" $BaseUrl"
    $browserInfo.UseShellExecute = $false
    $browserInfo.CreateNoWindow = $true
    $browserProcess = [Diagnostics.Process]::Start($browserInfo)

    $page = $null
    for ($i = 0; $i -lt 50 -and -not $page; $i++) {
        Start-Sleep -Milliseconds 200
        try {
            $pages = Invoke-RestMethod -Uri "http://127.0.0.1:$debugPort/json" -TimeoutSec 2
            $page = @($pages | Where-Object { $_.type -eq 'page' }) | Select-Object -First 1
        } catch { }
    }
    if (-not $page) { throw 'Browser debugging endpoint was not available.' }

    $socket = New-Object Net.WebSockets.ClientWebSocket
    $socket.ConnectAsync([Uri]$page.webSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null
    Send-Cdp 'Runtime.enable' | Out-Null
    Send-Cdp 'Page.enable' | Out-Null

    Send-Cdp 'Page.navigate' @{ url = $BaseUrl } | Out-Null
    Wait-For "document.readyState==='complete' && Boolean(document.querySelector('#explore'))"
    $public = Invoke-Eval "(async()=>{const root=new URL('$BaseUrl');const read=async path=>{const response=await fetch(new URL(path,root),{cache:'no-store'});return {status:response.status,text:await response.text()};};const indexResult=await read('data/genres/index.json');const genreResult=await read('$($entry.path)');const assetResponse=await fetch(new URL('$($entry.representativeAsset)',root),{cache:'no-store'});const assetBytes=(await assetResponse.arrayBuffer()).byteLength;const index=JSON.parse(indexResult.text);const genre=JSON.parse(genreResult.text);return {htmlStatus:performance.getEntriesByType('navigation')[0].responseStatus,title:document.title,indexStatus:indexResult.status,indexGenres:index.genres.length,indexCount:index.genres.find(x=>x.id==='$Genre').itemCount,genreStatus:genreResult.status,genreCount:genre.itemCount,genreItems:genre.items.length,representative:genre.representativeItemId,assetStatus:assetResponse.status,assetType:assetResponse.headers.get('content-type'),assetBytes};})()"

    Send-Cdp 'Page.navigate' @{ url = "$BaseUrl`?genre=$Genre" } | Out-Null
    Wait-For "document.querySelectorAll('.specimen').length===$expectedCount"
    $direct = Invoke-Eval "({status:performance.getEntriesByType('navigation')[0].responseStatus,url:location.search,cards:document.querySelectorAll('.specimen').length,title:document.querySelector('#collection-title').textContent})"

    $legacyResult = $null
    if ($legacy) {
        $legacyDate = [string]$legacy.Name
        Send-Cdp 'Page.navigate' @{ url = "$BaseUrl`?collection=$legacyDate" } | Out-Null
        Wait-For "location.search==='?genre=$Genre' && document.querySelectorAll('.specimen').length===$expectedCount"
        $legacyResult = Invoke-Eval "({status:performance.getEntriesByType('navigation')[0].responseStatus,url:location.search,cards:document.querySelectorAll('.specimen').length})"
    }

    $failed = $public.htmlStatus -ne 200 -or $public.indexStatus -ne 200 -or $public.indexCount -ne $expectedCount -or $public.genreStatus -ne 200 -or $public.genreCount -ne $expectedCount -or $public.genreItems -ne $expectedCount -or $public.assetStatus -ne 200 -or -not $public.assetType.StartsWith('image/') -or $public.assetBytes -lt 1000 -or $direct.status -ne 200 -or $direct.url -ne "?genre=$Genre" -or $direct.cards -ne $expectedCount
    if ($legacyResult -and ($legacyResult.status -ne 200 -or $legacyResult.url -ne "?genre=$Genre" -or $legacyResult.cards -ne $expectedCount)) { $failed = $true }
    $report = [ordered]@{ genre = $Genre; public = $public; direct = $direct; legacyRedirect = $legacyResult }
    $report | ConvertTo-Json -Depth 6
    if ($failed) { throw 'GitHub Pages verification failed.' }
}
finally {
    if ($socket) { $socket.Dispose() }
    if ($browserProcess -and -not $browserProcess.HasExited) { Stop-Process -Id $browserProcess.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 300
    $resolvedOutput = [IO.Path]::GetFullPath($output).TrimEnd('\') + '\'
    $resolvedProfile = [IO.Path]::GetFullPath($profile)
    if ($resolvedProfile.StartsWith($resolvedOutput, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedProfile)) {
        Remove-Item -LiteralPath $resolvedProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}
