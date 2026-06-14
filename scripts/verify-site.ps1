param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')]
    [string]$Genre,
    [switch]$KeepScreenshots
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $root 'output'
New-Item -ItemType Directory -Force -Path $output | Out-Null

function Get-FreePort { $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $listener.Start(); $port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port; $listener.Stop(); return $port }
$serverPort = Get-FreePort; $debugPort = Get-FreePort
$baseUrl = "http://127.0.0.1:$serverPort/"
$profile = Join-Path $output "chrome-profile-$PID"
$desktopShot = Join-Path $output "genre-map-$Genre.png"; $mobileShot = Join-Path $output "genre-mobile-$Genre.png"
$browserExe = @('C:\Program Files\Google\Chrome\Application\chrome.exe','C:\Program Files (x86)\Google\Chrome\Application\chrome.exe','C:\Program Files\Microsoft\Edge\Application\msedge.exe','C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $browserExe) { throw 'Chrome or Edge was not found.' }

$index = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data/genres/index.json') | ConvertFrom-Json
$entry = @($index.genres | Where-Object { $_.id -eq $Genre }) | Select-Object -First 1
if (-not $entry) { throw "Genre not found: $Genre" }
$genreData = Get-Content -Raw -Encoding UTF8 (Join-Path $root $entry.path) | ConvertFrom-Json
$expectedCount = @($genreData.items).Count
$publishedCount = @($index.genres | Where-Object { $_.status -eq 'published' }).Count
$legacy = $index.legacyCollections.PSObject.Properties | Where-Object { $_.Value -eq $Genre } | Select-Object -First 1
$serverProcess = $null; $browserProcess = $null; $socket = $null; $nextId = 0

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
function Wait-For([string]$expression) { for ($attempt = 0; $attempt -lt 50; $attempt++) { if (Invoke-Eval $expression) { return }; Start-Sleep -Milliseconds 200 }; throw "Timed out waiting for: $expression" }
function Save-Screenshot([string]$path) { $shot = Send-Cdp 'Page.captureScreenshot' @{ format = 'png'; captureBeyondViewport = $false }; [IO.File]::WriteAllBytes($path, [Convert]::FromBase64String($shot.data)) }

try {
    $serverInfo = New-Object Diagnostics.ProcessStartInfo; $serverInfo.FileName = (Get-Command python).Source; $serverInfo.Arguments = "-m http.server $serverPort --bind 127.0.0.1"; $serverInfo.WorkingDirectory = $root; $serverInfo.UseShellExecute = $false; $serverInfo.CreateNoWindow = $true
    $serverProcess = [Diagnostics.Process]::Start($serverInfo)
    for ($attempt = 0; $attempt -lt 20; $attempt++) { if ((& curl.exe -sS -o NUL -w '%{http_code}' $baseUrl) -eq '200') { break }; Start-Sleep -Milliseconds 250 }
    $browserInfo = New-Object Diagnostics.ProcessStartInfo; $browserInfo.FileName = $browserExe; $browserInfo.Arguments = "--headless=new --disable-gpu --no-sandbox --no-first-run --no-default-browser-check --remote-debugging-port=$debugPort --user-data-dir=`"$profile`" --window-size=1440,1000 $baseUrl"; $browserInfo.UseShellExecute = $false; $browserInfo.CreateNoWindow = $true
    $browserProcess = [Diagnostics.Process]::Start($browserInfo)
    $page = $null
    for ($attempt = 0; $attempt -lt 30; $attempt++) { try { $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$debugPort/json" -TimeoutSec 2; $page = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1; if ($page) { break } } catch {}; Start-Sleep -Milliseconds 400 }
    if (-not $page) { throw 'Browser debugging endpoint was not available.' }
    $socket = New-Object Net.WebSockets.ClientWebSocket; $socket.ConnectAsync([Uri]$page.webSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null
    Send-Cdp 'Runtime.enable' | Out-Null; Send-Cdp 'Page.enable' | Out-Null
    Send-Cdp 'Page.addScriptToEvaluateOnNewDocument' @{ source = "window.__verificationErrors=[];addEventListener('error',e=>window.__verificationErrors.push(e.message));addEventListener('unhandledrejection',e=>window.__verificationErrors.push(String(e.reason)));" } | Out-Null

    Send-Cdp 'Page.navigate' @{ url = $baseUrl } | Out-Null
    Wait-For "document.querySelectorAll('.genre-node').length===$publishedCount"
    $map = Invoke-Eval "(async()=>{const ready=async id=>{for(let i=0;i<80;i++){const p=document.querySelector('#genre-preview');if(p.dataset.genre===id&&p.dataset.ready==='true')return true;await new Promise(r=>setTimeout(r,50));}return false;};const n=[...document.querySelectorAll('.genre-node')];const before=n.map(x=>({id:x.dataset.genre,left:x.style.left,top:x.style.top}));n[0].click();await ready(n[0].dataset.genre);await Promise.all([...document.querySelectorAll('.preview-specimens img')].map(i=>i.complete?true:new Promise(r=>{i.addEventListener('load',r,{once:true});i.addEventListener('error',r,{once:true})})));const broken=[...document.querySelectorAll('.preview-specimens img')].filter(i=>i.naturalWidth===0).map(i=>i.src);const selected=Boolean(document.querySelector('.genre-node.selected'));const select=document.querySelector('#map-tag-select');const tag=[...select.options].slice(1).find(o=>n.some(x=>!x.dataset.tags.split('|').includes(o.value)));if(tag){select.value=tag.value;select.dispatchEvent(new Event('change',{bubbles:true}));await ready(state.selected);}const filtered=n.filter(x=>x.classList.contains('filtered')).length;const specimen=document.querySelector('.preview-specimens button');specimen.click();const dialogOpened=document.querySelector('#specimen-dialog').open;document.querySelector('.dialog-close').click();const related=document.querySelector('.preview-related button');const selectedBefore=state.selected;if(related){const target=related.dataset.related;related.click();await ready(target);}const relatedChanged=!related||state.selected!==selectedBefore;document.querySelector('#random-genre').click();await ready(state.selected);return {nodes:n.length,lines:document.querySelectorAll('.map-lines line').length,filtered,selected,preview:Boolean(document.querySelector('.open-selected')),previewSpecimens:document.querySelectorAll('.preview-specimens button').length,brokenPreviewImages:broken.length,brokenPreviewSources:broken,dialogOpened,relatedChanged,positions:before,errors:window.__verificationErrors};})()"
    $layout = Invoke-Eval "(()=>{const original=state.published;const fixture=Array.from({length:14},(_,i)=>({id:'fixture-'+i,tags:['shared-'+(i%4),'group-'+(i%3)],relatedGenres:i?['fixture-'+(i-1)]:[]}));state.published=fixture;const first=[...computePositions(fixture).values()].map(p=>({id:p.id,x:p.x,y:p.y}));const second=[...computePositions(fixture).values()].map(p=>({id:p.id,x:p.x,y:p.y}));state.published=original;let min=999;for(let i=0;i<first.length;i++)for(let j=i+1;j<first.length;j++)min=Math.min(min,Math.hypot(first[i].x-first[j].x,first[i].y-first[j].y));document.querySelector('#toggle-view').click();const listCards=document.querySelectorAll('.genre-list-card').length;const listVisible=!document.querySelector('#genre-list').hidden;document.querySelector('#toggle-view').click();return {deterministic:JSON.stringify(first)===JSON.stringify(second),minimumDistance:min,listCards,listVisible};})()"
    if ($KeepScreenshots) { Invoke-Eval "document.documentElement.style.scrollBehavior='auto';scrollTo(0,document.querySelector('#explore').offsetTop);Promise.all([...document.images].map(i=>i.complete?true:new Promise(r=>{i.addEventListener('load',r,{once:true});i.addEventListener('error',r,{once:true})})))" | Out-Null; Start-Sleep -Milliseconds 500; Save-Screenshot $desktopShot }

    Send-Cdp 'Page.navigate' @{ url = "$baseUrl`?genre=$Genre" } | Out-Null
    Wait-For "document.querySelectorAll('.specimen').length===$expectedCount"
    $detail = Invoke-Eval "(()=>{const first=document.querySelector('.specimen');first.click();const source=document.querySelector('.source-button');const filter=document.querySelectorAll('.filter-button')[1];document.querySelector('.dialog-close').click();filter.click();const result={url:location.search,title:document.querySelector('#collection-title').textContent,cards:document.querySelectorAll('.specimen').length,visible:[...document.querySelectorAll('.specimen')].filter(x=>!x.hidden).length,history:document.querySelectorAll('.genre-history li').length,related:document.querySelectorAll('.related-genres button').length,source:source.href,target:source.target,errors:window.__verificationErrors};document.querySelector('.back-to-map').click();result.mapAfterBack=!document.querySelector('#explore').hidden;history.back();return result;})()"
    Start-Sleep -Milliseconds 400
    $historyResult = Invoke-Eval "({genreVisible:!document.querySelector('#genre-view').hidden,url:location.search})"

    $legacyResult = $null
    if ($legacy) {
        $legacyDate = [string]$legacy.Name
        Send-Cdp 'Page.navigate' @{ url = "$baseUrl`?collection=$legacyDate" } | Out-Null
        Wait-For "document.querySelectorAll('.specimen').length===$expectedCount"
        $legacyResult = Invoke-Eval "({url:location.search,cards:document.querySelectorAll('.specimen').length})"
    }

    Send-Cdp 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 1; mobile = $true } | Out-Null
    Send-Cdp 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-reduced-motion'; value = 'reduce' }) } | Out-Null
    Send-Cdp 'Page.navigate' @{ url = $baseUrl } | Out-Null
    Wait-For "document.querySelectorAll('.genre-node').length===$publishedCount"
    $mobile = Invoke-Eval "({clientWidth:document.documentElement.clientWidth,scrollWidth:document.documentElement.scrollWidth,noOverflow:document.documentElement.scrollWidth<=document.documentElement.clientWidth,nodes:document.querySelectorAll('.genre-node').length,panel:getComputedStyle(document.querySelector('.genre-preview')).position,reducedMotion:parseFloat(getComputedStyle(document.querySelector('.genre-node')).animationDuration)<=0.01,errors:window.__verificationErrors})"
    if ($KeepScreenshots) { Save-Screenshot $mobileShot }

    $failed = $map.nodes -ne $publishedCount -or $map.lines -lt 1 -or $map.filtered -lt 1 -or -not $map.selected -or -not $map.preview -or $map.previewSpecimens -lt 1 -or $map.brokenPreviewImages -ne 0 -or -not $map.dialogOpened -or -not $map.relatedChanged -or @($map.errors).Count -ne 0 -or -not $layout.deterministic -or $layout.minimumDistance -lt 16 -or -not $layout.listVisible -or $layout.listCards -ne $publishedCount -or $detail.cards -ne $expectedCount -or $detail.visible -lt 1 -or $detail.history -lt 1 -or -not $detail.source.StartsWith('http') -or $detail.target -ne '_blank' -or -not $detail.mapAfterBack -or -not $historyResult.genreVisible -or @($detail.errors).Count -ne 0 -or -not $mobile.noOverflow -or $mobile.nodes -ne $publishedCount -or $mobile.panel -ne 'absolute' -or -not $mobile.reducedMotion -or @($mobile.errors).Count -ne 0
    if ($legacyResult -and ($legacyResult.url -ne "?genre=$Genre" -or $legacyResult.cards -ne $expectedCount)) { $failed = $true }
    $report = [ordered]@{ genre = $Genre; map = $map; layoutFixture = $layout; detail = $detail; browserHistory = $historyResult; legacyRedirect = $legacyResult; mobile = $mobile; screenshots = if ($KeepScreenshots) { @($desktopShot, $mobileShot) } else { @() } }
    $report | ConvertTo-Json -Depth 8
    if ($failed) { throw 'Browser verification failed.' }
}
finally {
    if ($socket) { $socket.Dispose() }
    if ($browserProcess -and -not $browserProcess.HasExited) { Stop-Process -Id $browserProcess.Id -Force -ErrorAction SilentlyContinue }
    if ($serverProcess -and -not $serverProcess.HasExited) { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 300
    $resolvedOutput = [IO.Path]::GetFullPath($output).TrimEnd('\') + '\'; $resolvedProfile = [IO.Path]::GetFullPath($profile)
    if ($resolvedProfile.StartsWith($resolvedOutput, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedProfile)) { Remove-Item -LiteralPath $resolvedProfile -Recurse -Force -ErrorAction SilentlyContinue }
}
