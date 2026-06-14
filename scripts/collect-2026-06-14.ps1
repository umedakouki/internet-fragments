$ErrorActionPreference = "Stop"

$root = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
$imageDir = Join-Path $root "assets/collections/2026-06-14"
$dataDir = Join-Path $root "data/collections"
New-Item -ItemType Directory -Force -Path $imageDir, $dataDir | Out-Null
$userAgent = 'InternetFragmentsCollector/1.0 (personal cultural archive)'

function Invoke-CurlJson([string]$uri) {
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        $raw = & curl.exe --ssl-no-revoke -k -L --fail --silent --show-error `
            --connect-timeout 12 --max-time 45 -A $userAgent $uri
        if ($LASTEXITCODE -eq 0 -and $raw) { return ($raw | ConvertFrom-Json) }
        if ($attempt -eq 4) { throw "Failed to fetch JSON after $attempt attempts: $uri" }
        Start-Sleep -Seconds (5 * $attempt)
    }
}

function Save-RemoteFile([string]$uri, [string]$fallbackUri, [string]$destination) {
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        $candidate = if ($attempt -le 3) { $uri } else { $fallbackUri }
        & curl.exe --ssl-no-revoke -k -L --fail --silent --show-error `
            --connect-timeout 12 --max-time 60 -A $userAgent $candidate -o $destination
        if ($LASTEXITCODE -eq 0 -and (Test-Path $destination) -and (Get-Item $destination).Length -gt 0) {
            return
        }
        if ($attempt -eq 5) { throw "Failed to download image after $attempt attempts: $candidate" }
        Start-Sleep -Seconds (15 * $attempt)
    }
}

$selections = @(
    @{ title = 'File:Rainwater Head - geograph.org.uk - 1550161.jpg'; family = '雨水頭'; note = '教会の改修年1770とイニシャルが、排水部材を小さな建築銘板に変えている。' },
    @{ title = 'File:Rainwater head, Topsham - geograph.org.uk - 2156318.jpg'; family = '雨水頭'; note = '壁面設備の実用品に、所有者や年代を示す装飾が組み込まれた例。' },
    @{ title = 'File:Rainwater head, Bovey Tracey - geograph.org.uk - 2198297.jpg'; family = '雨水頭'; note = '雨水の入口が、建物正面の記憶を留める縦長の標本になっている。' },
    @{ title = 'File:Rainwater head at Howick Hall - geograph.org.uk - 2975675.jpg'; family = '雨水頭'; note = '邸宅の外壁で、紋章的な意匠と排水機能が同じ鋳物に重なる。' },
    @{ title = 'File:Rainwater head, Muswell Hill Telephone Exchange - geograph.org.uk - 2057463.jpg'; family = '雨水頭'; note = '通信施設の建築年を、目立たない雨水部材が現在まで運んでいる。' },
    @{ title = 'File:Rainwater head, Dowsby Hall.jpg'; family = '雨水頭'; note = '1630年の年号が残る初期例で、住宅史と設備史を一点で結ぶ。' },
    @{ title = 'File:Fort George, rainwater head - geograph.org.uk - 6285268.jpg'; family = '雨水頭'; note = '軍事建築の規律的な壁面に、鋳造文字が小さな年代層を作る。' },
    @{ title = 'File:Highfields Schools – Rainwater head - geograph.org.uk - 5643454.jpg'; family = '雨水頭'; note = '学校建築の公共性が、校名板ではなく排水設備の装飾にも現れる。'; fallback = 'https://t0.geograph.org.uk/stamped/5643454_56323961.jpg' },
    @{ title = 'File:Old rainwater hopper-head, Fournier Street, Spitalfields - geograph.org.uk - 2403559.jpg'; family = 'ホッパー'; note = '街路から見落としやすい高所の器具に、地区の時間が凝縮されている。'; fallback = 'https://t0.geograph.org.uk/stamped/2403559_00ff85f8.jpg' },
    @{ title = 'File:20 Colegate - dated rainwater head - geograph.org.uk - 5918139.jpg'; family = '雨水頭'; note = '番地のある建物と日付入り部材を直接対応させられる都市資料。'; fallback = 'https://t0.geograph.org.uk/stamped/5918139_43144d35.jpg' },
    @{ title = 'File:Cricklade, St. Sampson''s Church, Clearly dated rainwater hopper - geograph.org.uk - 5443169.jpg'; family = 'ホッパー'; note = '遠目でも読める年号が、教会の改修履歴を外壁に掲示している。'; fallback = 'https://t0.geograph.org.uk/stamped/5443169_ac1fa817.jpg' },
    @{ title = 'File:Dated drainpipe, Belfast - geograph.org.uk - 1405661.jpg'; family = '縦樋'; note = '大学施設の縦樋に残る日付が、設備交換を免れた建築の署名になる。'; fallback = 'https://t0.geograph.org.uk/stamped/1405661_ae65bc71.jpg' },
    @{ title = 'File:Drainpipe embellishment, dated 1867 - geograph.org.uk - 257788.jpg'; family = '縦樋'; note = '1867年の装飾が、細い配管を壁面の記念物へ変えている。'; fallback = 'https://t0.geograph.org.uk/stamped/257788_26a2f9b8.jpg' }
)

function PlainText([object]$value) {
    if ($null -eq $value) { return '' }
    $text = ([System.Net.WebUtility]::HtmlDecode(([regex]::Replace([string]$value, '<[^>]+>', ' '))) -replace '\s+', ' ').Trim()
    return $text.Replace([char]0x92, "'")
}

$titleQuery = ($selections | ForEach-Object { [uri]::EscapeDataString($_.title) }) -join '%7C'
$api = "https://commons.wikimedia.org/w/api.php?action=query&titles=$titleQuery&prop=imageinfo&iiprop=url%7Cmime%7Csize%7Cextmetadata&iiurlwidth=1000&format=json&origin=*"
$response = Invoke-CurlJson $api
$pageByTitle = @{}
foreach ($candidatePage in $response.query.pages.PSObject.Properties.Value) {
    $pageByTitle[$candidatePage.title] = $candidatePage
}

$items = @()
foreach ($selection in $selections) {
    $page = $pageByTitle[$selection.title]
    if (-not $page.imageinfo) { throw "No image information returned for $($selection.title)" }

    $info = $page.imageinfo[0]
    $meta = $info.extmetadata
    $extension = [IO.Path]::GetExtension(([uri]$info.thumburl).AbsolutePath)
    if (-not $extension) { $extension = '.jpg' }
    $filename = ('{0:D4}{1}' -f [int]$page.pageid, $extension.ToLowerInvariant())
    $destination = Join-Path $imageDir $filename
    $redirectName = [uri]::EscapeDataString(($selection.title -replace '^File:', ''))
    $downloadUrl = "https://commons.wikimedia.org/wiki/Special:Redirect/file/$redirectName`?width=1000"
    if (-not (Test-Path $destination) -or (Get-Item $destination).Length -eq 0) {
        $primaryDownload = if ($selection.fallback) { $selection.fallback } else { $info.thumburl }
        Save-RemoteFile $primaryDownload $downloadUrl $destination
    }

    $items += [ordered]@{
        id = [string]$page.pageid
        title = ($page.title -replace '^File:', '')
        family = $selection.family
        curatorNote = $selection.note
        localImage = "assets/collections/2026-06-14/$filename"
        sourceUrl = $info.descriptionurl
        originalUrl = $info.url
        artist = PlainText $meta.Artist.value
        credit = PlainText $meta.Credit.value
        license = PlainText $meta.LicenseShortName.value
        licenseUrl = $meta.LicenseUrl.value
        description = PlainText $meta.ImageDescription.value
        date = PlainText $meta.DateTimeOriginal.value
        width = $info.width
        height = $info.height
    }
    Start-Sleep -Seconds 4
}

$collection = [ordered]@{
    date = '2026-06-14'
    title = '雨樋に刻まれた建築年'
    subtitle = '雨水頭・ホッパー・縦樋に残る日付鋳物'
    description = '屋根から水を逃がすための雨水頭、ホッパー、縦樋のうち、年号、頭文字、紋章的装飾を備えた例を集めた。交換されやすい設備部材が残ることで、建築の竣工、改修、所有の記憶が外壁に小さく固定される。'
    method = 'Wikimedia Commonsで rainwater head、dated rainwater hopper、dated drainpipe を横断検索し、年号または年代を示す意匠を確認でき、作者と再利用条件を追跡できる英国の事例を選定した。'
    itemCount = $items.Count
    items = $items
}

$json = $collection | ConvertTo-Json -Depth 8
$jsonPath = Join-Path $dataDir '2026-06-14.json'
[IO.File]::WriteAllText($jsonPath, $json, (New-Object Text.UTF8Encoding($false)))
Write-Output "Saved $($items.Count) items to $jsonPath"
