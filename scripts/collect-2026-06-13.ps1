$ErrorActionPreference = "Stop"

$root = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
$imageDir = Join-Path $root "assets/collections/2026-06-13"
$dataDir = Join-Path $root "data/collections"
New-Item -ItemType Directory -Force -Path $imageDir, $dataDir | Out-Null
$headers = @{ 'User-Agent' = 'InternetFragmentsCollector/1.0 (personal cultural archive)' }

function Invoke-CommonsJson([string]$uri) {
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try { return Invoke-RestMethod -Uri $uri -Headers $headers }
        catch {
            if ($attempt -eq 4) { throw }
            Start-Sleep -Seconds (5 * $attempt)
        }
    }
}

function Save-RemoteFile([string]$uri, [string]$fallbackUri, [string]$destination) {
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            $candidate = if ($attempt -lt 3) { $uri } else { $fallbackUri }
            & curl.exe -L --fail --silent --show-error --connect-timeout 12 --max-time 45 -A $headers['User-Agent'] $candidate -o $destination
            if ($LASTEXITCODE -ne 0) { throw "curl failed with exit code $LASTEXITCODE" }
            return
        }
        catch {
            if ($attempt -eq 4) { throw }
            Start-Sleep -Seconds (8 * $attempt)
        }
    }
}

$selections = @(
    @{ title = 'File:Hentaigana on sign - Kanagawa - 2024 April 21.jpeg'; family = '変体仮名'; note = '現代の案内表示に、標準化以前の仮名の気配が残る。' },
    @{ title = 'File:A Board of Restaurant "Yoshidaya” with the name written in Hentaigana, near Arashiyama.JPG'; family = '変体仮名'; note = '店名という短い文字列が、古い字形を現在の街路へ運んでいる。' },
    @{ title = 'File:Straubing, Nasenschild Zum Bayerischen Löwen, 2.jpeg'; family = 'フラクトゥール'; note = '装飾看板と古書体が一体化し、歴史性を店の顔として使っている。' },
    @{ title = 'File:Wien, Mölker Steig, Haardt und Krüger -- 2018 -- 3090.jpg'; family = 'フラクトゥール'; note = '都市の壁面に残る商業文字。読ませる文字と雰囲気を作る文字の中間にある。' },
    @{ title = 'File:Ebersberg, Schild Faßlmetzger, 1.jpeg'; family = 'フラクトゥール'; note = '肉屋の業種表示が、土地の記憶を示す書体見本にもなっている。' },
    @{ title = 'File:Pleinfeld, Nasenschild mit Krone, 1.jpeg'; family = 'フラクトゥール'; note = '王冠の図像と文字が、遠目でも読める小さな紋章を作る。' },
    @{ title = 'File:Berchtesgaden, Goldener Bär, 1.jpeg'; family = 'フラクトゥール'; note = '店名、動物像、金属細工が一つの読み物として路上に突き出す。' },
    @{ title = 'File:Mühldorf, Nasenschild Stadtplatz 4, 2.jpeg'; family = 'フラクトゥール'; note = '短命な商業看板が、保存される都市工芸へ変わった例。' },
    @{ title = 'File:Würzburg, zur alten Wache, Nasenschild, 1.jpeg'; family = 'フラクトゥール'; note = '「古さ」を伝える語と書体が重なり、時間の演出が強まっている。' },
    @{ title = 'File:Torgau Leipziger Strasse 6.jpg'; family = 'フラクトゥール'; note = '建物の履歴と現在の営業表示が同じ壁面に積層する。' },
    @{ title = 'File:2014-06 Amberes.jpg'; family = 'ブラックレター'; note = '国境を越えて流通する古書体が、街のブランド記号として働く。' },
    @{ title = 'File:Maison des Associations Genève-3-Vieux-Billard.jpg'; family = 'ブラックレター'; note = '公共的な施設名にも、制度的でない文字の個性が残る。' },
    @{ title = 'File:Norderney, Marienhöhe -- 2025 -- 9295-9.jpg'; family = '歴史的字形'; note = '観光地の現在と、過去を想起させる文字設計が同居する。' },
    @{ title = 'File:Herzberg am Harz Junkernstrasse.jpg'; family = '歴史的字形'; note = '通りの情報が、地域固有の文字景観として記録されている。' },
    @{ title = 'File:August Rietz Bokhandel, Södermalmstorg 4, 1920-tal.jpg'; family = '歴史資料'; note = '現代看板の比較対象となる、1920年代の書店ファサード。' }
)

function PlainText([object]$value) {
    if ($null -eq $value) { return '' }
    return ([System.Net.WebUtility]::HtmlDecode(([regex]::Replace([string]$value, '<[^>]+>', ' '))) -replace '\s+', ' ').Trim()
}

$titleQuery = ($selections | ForEach-Object { [uri]::EscapeDataString($_.title) }) -join '%7C'
$batchApi = "https://commons.wikimedia.org/w/api.php?action=query&titles=$titleQuery&prop=imageinfo&iiprop=url%7Cmime%7Csize%7Cextmetadata&iiurlwidth=1200&format=json&origin=*"
$batchResponse = Invoke-CommonsJson $batchApi
$pageByTitle = @{}
foreach ($candidatePage in $batchResponse.query.pages.PSObject.Properties.Value) {
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
    $downloadUrl = "https://commons.wikimedia.org/wiki/Special:Redirect/file/$redirectName`?width=1200"
    if (-not (Test-Path $destination) -or (Get-Item $destination).Length -eq 0) {
        Save-RemoteFile $downloadUrl $info.thumburl $destination
    }

    $items += [ordered]@{
        id = [string]$page.pageid
        title = ($page.title -replace '^File:', '')
        family = $selection.family
        curatorNote = $selection.note
        localImage = "assets/collections/2026-06-13/$filename"
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
    Start-Sleep -Milliseconds 1800
}

$collection = [ordered]@{
    date = '2026-06-13'
    title = '街角の異体字標本'
    subtitle = '現代の看板に生き残る旧字・廃字・古書体'
    description = '標準化された文字の外側で、変体仮名、フラクトゥール、ブラックレターなどが店名や地名として生き続ける例を集めた。文字そのものだけでなく、建物、商い、観光、郷土意識との結びつきを観察する。'
    method = 'Wikimedia Commonsを複数の文字史キーワードで横断検索し、街路・店舗・施設の実景を中心に選定。比較用の歴史写真を1件含む。'
    itemCount = $items.Count
    items = $items
}

$json = $collection | ConvertTo-Json -Depth 8
$jsonPath = Join-Path $dataDir '2026-06-13.json'
[IO.File]::WriteAllText($jsonPath, $json, (New-Object Text.UTF8Encoding($false)))
Write-Output "Saved $($items.Count) items to $jsonPath"
