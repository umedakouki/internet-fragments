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
$desktopShot = Join-Path $output "explore-desktop-$Genre.png"
$mobileShot = Join-Path $output "explore-mobile-$Genre.png"
$browserExe = @('C:\Program Files\Google\Chrome\Application\chrome.exe','C:\Program Files (x86)\Google\Chrome\Application\chrome.exe','C:\Program Files\Microsoft\Edge\Application\msedge.exe','C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $browserExe) { throw 'Chrome or Edge was not found.' }

$index = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data/genres/index.json') | ConvertFrom-Json
$entry = @($index.genres | Where-Object { $_.id -eq $Genre }) | Select-Object -First 1
if (-not $entry) { throw "Genre not found: $Genre" }
$genreData = Get-Content -Raw -Encoding UTF8 (Join-Path $root $entry.path) | ConvertFrom-Json
$firstItemId = [string]$genreData.items[0].id
$publishedCount = @($index.genres | Where-Object { $_.status -eq 'published' }).Count
$specimenCount = @($index.genres | Where-Object { $_.status -eq 'published' } | ForEach-Object { [int]$_.itemCount } | Measure-Object -Sum).Sum
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
function Wait-For([string]$expression) { for ($attempt = 0; $attempt -lt 80; $attempt++) { if (Invoke-Eval $expression) { return }; Start-Sleep -Milliseconds 150 }; throw "Timed out waiting for: $expression" }
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
    $initial = Invoke-Eval "(()=>({title:document.title,overview:Boolean(document.querySelector('.site-overview')),noIntroActions:!document.querySelector('#start-exploration')&&!document.querySelector('[data-list-start]'),genreLabel:document.querySelector('.zone-title h2').textContent.trim(),exploreLabel:document.querySelector('.panel-zone-title h2').textContent.trim(),empty:document.querySelector('#exploration-panel').dataset.state==='empty',noDialog:!document.querySelector('dialog'),noGenrePage:!document.querySelector('#genre-view'),nodes:document.querySelectorAll('.genre-node').length,errors:window.__verificationErrors}))()"

    $genreFlow = Invoke-Eval "(async()=>{const node=[...document.querySelectorAll('.genre-node')].find(x=>x.dataset.genre==='$Genre');node.click();for(let i=0;i<80&&document.querySelector('#exploration-panel').dataset.state!=='genre';i++)await new Promise(r=>setTimeout(r,80));const genreUrl=location.search;const samples=document.querySelectorAll('.specimen-card').length;document.querySelector('.specimen-card').click();for(let i=0;i<100&&document.querySelectorAll('#branch-options button').length<3;i++)await new Promise(r=>setTimeout(r,80));const itemUrl=location.search;const branches=[...document.querySelectorAll('#branch-options button')].map(x=>x.dataset.branchGenre+':'+x.dataset.branchItem);const source=document.querySelector('.source-button').href;const target=document.querySelector('.source-button').target;const recordDate=document.querySelector('.metadata dd').textContent.trim();const onlyRecordDate=document.querySelectorAll('.metadata div').length===1&&document.querySelector('.metadata dt').textContent.trim().length>0;const dock=document.querySelector('.item-explore-dock');const controlsAtTop=dock.compareDocumentPosition(document.querySelector('.item-media'))&Node.DOCUMENT_POSITION_FOLLOWING;const before=itemUrl;const next=document.querySelector('[data-next]:not(:disabled)');if(next){next.click();await new Promise(r=>setTimeout(r,80));history.back();for(let i=0;i<60&&location.search!==before;i++)await new Promise(r=>setTimeout(r,80));}const backRestored=location.search===before;const branch=document.querySelector('#branch-options button');const branchKey=branch.dataset.branchGenre+':'+branch.dataset.branchItem;branch.click();for(let i=0;i<80&&document.querySelector('#exploration-panel').dataset.genre+':'+document.querySelector('#exploration-panel').dataset.item!==branchKey;i++)await new Promise(r=>setTimeout(r,80));return {genreUrl,itemUrl,samples,state:document.querySelector('#exploration-panel').dataset.state,branches:branches.length,uniqueBranches:new Set(branches).size,source,target,recordDate,onlyRecordDate,controlsAtTop:Boolean(controlsAtTop),trail:document.querySelectorAll('.trail-list button').length,backRestored,branchChanged:document.querySelector('#exploration-panel').dataset.genre+':'+document.querySelector('#exploration-panel').dataset.item===branchKey,stored:Boolean(sessionStorage.getItem('yohaku.exploration.v1')),errors:window.__verificationErrors};})()"

    $controls = Invoke-Eval "(()=>{document.querySelector('[data-view=list]').click();const listVisible=!document.querySelector('#genre-list').hidden;const listCards=document.querySelectorAll('.genre-list-card').length;document.querySelector('[data-view=map]').click();const details=document.querySelector('#tag-filter');details.open=true;const select=details.querySelector('select');const nodes=[...document.querySelectorAll('.genre-node')];const option=[...select.options].slice(1).find(o=>nodes.some(n=>!n.dataset.tags.split('|').includes(o.value)));if(option){select.value=option.value;select.dispatchEvent(new Event('change',{bubbles:true}));}return {listVisible,listCards,mapVisible:!document.querySelector('#genre-map').hidden,tagOpen:details.open,filtered:document.querySelectorAll('.genre-node.filtered').length};})()"
    $dateFormats = Invoke-Eval "(async()=>{const specimens=await allSpecimens();const values=specimens.map(x=>formatRecordDate(x.item.date));const invalid=values.filter(x=>/QS:|Taken on| date /i.test(x));const dates=[...document.querySelectorAll('#recent-updates time')].map(x=>x.textContent.trim());return {count:values.length,invalid:invalid.length,updatesDescending:dates.every((x,i)=>i===0||dates[i-1]>=x)};})()"

    $layout = Invoke-Eval "(()=>{const original=state.published;const fixture=Array.from({length:14},(_,i)=>({id:'fixture-'+i,tags:['shared-'+(i%4),'group-'+(i%3)],relatedGenres:i?['fixture-'+(i-1)]:[]}));const first=[...computePositions(fixture).values()].map(p=>({id:p.id,x:p.x,y:p.y}));const second=[...computePositions(fixture).values()].map(p=>({id:p.id,x:p.x,y:p.y}));let min=999;for(let i=0;i<first.length;i++)for(let j=i+1;j<first.length;j++)min=Math.min(min,Math.hypot(first[i].x-first[j].x,first[i].y-first[j].y));state.published=original;return {deterministic:JSON.stringify(first)===JSON.stringify(second),minimumDistance:min};})()"

    Send-Cdp 'Page.navigate' @{ url = "$baseUrl`?genre=$Genre&item=$firstItemId" } | Out-Null
    Wait-For "document.querySelector('#exploration-panel').dataset.state==='item'"
    $direct = Invoke-Eval "({url:location.search,genre:document.querySelector('#exploration-panel').dataset.genre,item:document.querySelector('#exploration-panel').dataset.item,branches:document.querySelectorAll('#branch-options button').length})"

    if ($legacy) {
        $legacyDate = [string]$legacy.Name
        Send-Cdp 'Page.navigate' @{ url = "$baseUrl`?collection=$legacyDate" } | Out-Null
        Wait-For "location.search==='?genre=$Genre' && document.querySelector('#exploration-panel').dataset.state==='genre'"
        $legacyResult = Invoke-Eval "({url:location.search,state:document.querySelector('#exploration-panel').dataset.state})"
    } else { $legacyResult = $null }

    Send-Cdp 'Emulation.setDeviceMetricsOverride' @{ width = 390; height = 844; deviceScaleFactor = 1; mobile = $true } | Out-Null
    Send-Cdp 'Page.navigate' @{ url = "$baseUrl`?genre=$Genre&item=$firstItemId" } | Out-Null
    Wait-For "document.querySelector('#exploration-panel').dataset.state==='item'"
    $mobile = Invoke-Eval "(()=>{const map=document.querySelector('#genre-map').getBoundingClientRect();const panel=document.querySelector('#exploration-panel').getBoundingClientRect();return {clientWidth:document.documentElement.clientWidth,scrollWidth:document.documentElement.scrollWidth,noOverflow:document.documentElement.scrollWidth<=document.documentElement.clientWidth,panelOverflow:getComputedStyle(document.querySelector('#exploration-panel')).overflowY,panelAfterMap:panel.top>=map.bottom-2,dockPosition:getComputedStyle(document.querySelector('.item-explore-dock')).position,branches:document.querySelectorAll('#branch-options button').length,errors:window.__verificationErrors};})()"
    if ($KeepScreenshots) { Save-Screenshot $mobileShot }

    Send-Cdp 'Emulation.setDeviceMetricsOverride' @{ width = 1440; height = 1000; deviceScaleFactor = 1; mobile = $false } | Out-Null
    Send-Cdp 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'prefers-reduced-motion'; value = 'reduce' }) } | Out-Null
    Send-Cdp 'Page.navigate' @{ url = $baseUrl } | Out-Null
    Wait-For "document.querySelectorAll('.genre-node').length===$publishedCount"
    $motion = Invoke-Eval "({reduced:parseFloat(getComputedStyle(document.querySelector('.genre-node')).animationDuration)<=0.01,errors:window.__verificationErrors})"
    if ($KeepScreenshots) { Invoke-Eval "scrollTo(0,0);true" | Out-Null; Start-Sleep -Milliseconds 300; Save-Screenshot $desktopShot }

    $failed = -not $initial.overview -or -not $initial.noIntroActions -or [string]::IsNullOrWhiteSpace([string]$initial.genreLabel) -or [string]::IsNullOrWhiteSpace([string]$initial.exploreLabel) -or -not $initial.empty -or -not $initial.noDialog -or -not $initial.noGenrePage -or $initial.nodes -ne $publishedCount -or @($initial.errors).Count -ne 0
    $failed = $failed -or $genreFlow.genreUrl -ne "?genre=$Genre" -or -not $genreFlow.itemUrl.Contains("genre=$Genre&item=") -or $genreFlow.samples -lt 1 -or $genreFlow.state -ne 'item' -or $genreFlow.branches -ne 3 -or $genreFlow.uniqueBranches -ne 3 -or -not $genreFlow.source.StartsWith('http') -or $genreFlow.target -ne '_blank' -or [string]::IsNullOrWhiteSpace([string]$genreFlow.recordDate) -or -not $genreFlow.onlyRecordDate -or -not $genreFlow.controlsAtTop -or $genreFlow.trail -lt 2 -or -not $genreFlow.backRestored -or -not $genreFlow.branchChanged -or -not $genreFlow.stored -or @($genreFlow.errors).Count -ne 0
    $failed = $failed -or -not $controls.listVisible -or $controls.listCards -ne $publishedCount -or -not $controls.mapVisible -or -not $controls.tagOpen -or $controls.filtered -lt 1
    $failed = $failed -or $dateFormats.count -ne $specimenCount -or $dateFormats.invalid -ne 0 -or -not $dateFormats.updatesDescending
    $failed = $failed -or -not $layout.deterministic -or $layout.minimumDistance -lt 16
    $failed = $failed -or $direct.url -ne "?genre=$Genre&item=$firstItemId" -or $direct.genre -ne $Genre -or $direct.item -ne $firstItemId
    $failed = $failed -or -not $mobile.noOverflow -or $mobile.panelOverflow -ne 'visible' -or -not $mobile.panelAfterMap -or $mobile.dockPosition -ne 'sticky' -or $mobile.branches -ne 3 -or @($mobile.errors).Count -ne 0
    $failed = $failed -or -not $motion.reduced -or @($motion.errors).Count -ne 0
    if ($legacyResult -and ($legacyResult.url -ne "?genre=$Genre" -or $legacyResult.state -ne 'genre')) { $failed = $true }

    [pscustomobject]@{ initial = $initial; genreFlow = $genreFlow; controls = $controls; dateFormats = $dateFormats; layout = $layout; direct = $direct; legacy = $legacyResult; mobile = $mobile; motion = $motion } | ConvertTo-Json -Depth 8
    if ($failed) { throw 'Browser verification failed.' }
    Write-Host "Browser verification passed for $Genre."
} finally {
    if ($socket) { try { $socket.Dispose() } catch {} }
    if ($browserProcess -and -not $browserProcess.HasExited) { try { $browserProcess.Kill() } catch {} }
    if ($serverProcess -and -not $serverProcess.HasExited) { try { $serverProcess.Kill() } catch {} }
    Start-Sleep -Milliseconds 250
    if (Test-Path -LiteralPath $profile) { $resolved = [IO.Path]::GetFullPath($profile); if ($resolved.StartsWith([IO.Path]::GetFullPath($output), [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue } }
    if (-not $KeepScreenshots) { Remove-Item -LiteralPath $desktopShot,$mobileShot -Force -ErrorAction SilentlyContinue }
}
