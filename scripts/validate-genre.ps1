param(
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')]
    [string]$Genre,
    [switch]$All,
    [switch]$CheckLinks
)

$ErrorActionPreference = 'Stop'
if (-not $Genre -and -not $All) { throw 'Specify -Genre <genre-id> or -All.' }

$root = Split-Path -Parent $PSScriptRoot
$indexPath = Join-Path $root 'data/genres/index.json'
$errors = New-Object System.Collections.Generic.List[string]
$allowedStatuses = @('published', 'archived', 'merged')
$allowedMediaTypes = @('image', 'video', 'audio', 'text', 'link')
$seenIds = @{}
$seenSources = @{}
$seenAssets = @{}

function Add-Error([string]$message) { $script:errors.Add($message) }
function Require-Value([object]$value, [string]$label) {
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { Add-Error "Missing value: $label" }
}
function Test-HttpUrl([string]$value, [string]$label) {
    $uri = $null
    if (-not [Uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http', 'https')) { Add-Error "$label must be an absolute HTTP(S) URL: $value" }
}
function Test-Asset([string]$path, [string]$label) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    if ($path.Contains('..') -or -not $path.StartsWith('assets/', [StringComparison]::Ordinal)) { Add-Error "Unsafe asset path at $label`: $path"; return }
    if (-not (Test-Path -LiteralPath (Join-Path $root $path))) { Add-Error "Asset file not found: $path" }
    if ($seenAssets.ContainsKey($path)) { Add-Error "Duplicate local asset: $path" } else { $seenAssets[$path] = $true }
}
function Test-SourceLink([string]$url) {
    $pythonCode = @'
import sys
import urllib.error
import urllib.request

url = sys.argv[1]

def request(method):
    headers = {'User-Agent': 'InternetFragmentsValidator/3.0'}
    if method == 'GET':
        headers['Range'] = 'bytes=0-0'
    req = urllib.request.Request(url, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code

status = request('HEAD')
if status in (403, 405, 429):
    status = request('GET')
print(status)
raise SystemExit(0 if 200 <= status < 400 else 1)
'@
    $status = & python -c $pythonCode $url
    if ($LASTEXITCODE -ne 0 -or [int]$status -lt 200 -or [int]$status -ge 400) { Add-Error "Source link failed ($status): $url" }
    Start-Sleep -Milliseconds 350
}

if (-not (Test-Path -LiteralPath $indexPath)) { throw "Genre index not found: $indexPath" }
$index = Get-Content -Raw -Encoding UTF8 -LiteralPath $indexPath | ConvertFrom-Json
$entries = @($index.genres)
$entryById = @{}

foreach ($entry in $entries) {
    Require-Value $entry.id 'index.genres[].id'
    if ($entryById.ContainsKey([string]$entry.id)) { Add-Error "Duplicate genre id in index: $($entry.id)" } else { $entryById[[string]$entry.id] = $entry }
    Require-Value $entry.title "index.$($entry.id).title"
    if ($allowedStatuses -notcontains [string]$entry.status) { Add-Error "Invalid genre status: $($entry.id)=$($entry.status)" }
    if (@($entry.tags).Count -eq 0) { Add-Error "Genre has no tags: $($entry.id)" }
    if ($entry.status -eq 'merged') {
        Require-Value $entry.redirectTo "index.$($entry.id).redirectTo"
    } else {
        Require-Value $entry.path "index.$($entry.id).path"
        Require-Value $entry.representativeAsset "index.$($entry.id).representativeAsset"
    }
    if ($entry.mapPosition) {
        if ([double]$entry.mapPosition.x -lt 0 -or [double]$entry.mapPosition.x -gt 100 -or [double]$entry.mapPosition.y -lt 0 -or [double]$entry.mapPosition.y -gt 100) { Add-Error "mapPosition must be within 0..100: $($entry.id)" }
    }
}

foreach ($entry in $entries) {
    foreach ($relatedId in @($entry.relatedGenres)) {
        if (-not $entryById.ContainsKey([string]$relatedId)) { Add-Error "Unknown related genre: $($entry.id) -> $relatedId" }
        if ($relatedId -eq $entry.id) { Add-Error "Genre relates to itself: $($entry.id)" }
    }
    if ($entry.redirectTo -and -not $entryById.ContainsKey([string]$entry.redirectTo)) { Add-Error "Unknown redirect target: $($entry.id) -> $($entry.redirectTo)" }
}

foreach ($property in $index.legacyCollections.PSObject.Properties) {
    if (-not $entryById.ContainsKey([string]$property.Value)) { Add-Error "Legacy collection points to unknown genre: $($property.Name) -> $($property.Value)" }
}

$targets = if ($All) { @($entries | Where-Object { $_.status -ne 'merged' }) } else { @($entries | Where-Object { $_.id -eq $Genre }) }
if ($targets.Count -eq 0) { Add-Error "Genre not found: $Genre" }

# Global ownership and duplicate checks intentionally scan every concrete genre.
foreach ($entry in @($entries | Where-Object { $_.status -ne 'merged' })) {
    $path = Join-Path $root ([string]$entry.path)
    if (-not (Test-Path -LiteralPath $path)) { Add-Error "Genre file not found: $($entry.path)"; continue }
    $genreData = Get-Content -Raw -Encoding UTF8 -LiteralPath $path | ConvertFrom-Json
    if ($genreData.id -ne $entry.id) { Add-Error "Genre id does not match index: $($entry.id)" }
    Require-Value $genreData.title "$($entry.id).title"
    Require-Value $genreData.subtitle "$($entry.id).subtitle"
    Require-Value $genreData.description "$($entry.id).description"
    Require-Value $genreData.method "$($entry.id).method"
    Require-Value $genreData.createdAt "$($entry.id).createdAt"
    Require-Value $genreData.updatedAt "$($entry.id).updatedAt"
    if ($genreData.status -ne $entry.status) { Add-Error "Status does not match index: $($entry.id)" }
    if ((@($genreData.tags) -join '|') -ne (@($entry.tags) -join '|')) { Add-Error "Tags do not match index: $($entry.id)" }
    $items = @($genreData.items)
    if ([int]$genreData.itemCount -ne $items.Count -or [int]$entry.itemCount -ne $items.Count) { Add-Error "itemCount mismatch: $($entry.id)" }
    if ($entry.status -eq 'published' -and $items.Count -eq 0) { Add-Error "Published genre is empty: $($entry.id)" }
    if (-not (@($items.id) -contains [string]$genreData.representativeItemId)) { Add-Error "Representative item is missing: $($entry.id)" }
    $representativePath = [string]$entry.representativeAsset
    if ($representativePath.Contains('..') -or -not $representativePath.StartsWith('assets/', [StringComparison]::Ordinal) -or -not (Test-Path -LiteralPath (Join-Path $root $representativePath))) { Add-Error "Representative asset is missing or unsafe: $($entry.id)" }

    $history = @($genreData.history)
    if ($history.Count -eq 0) { Add-Error "Genre history is empty: $($entry.id)" }
    $historyDates = @($history | ForEach-Object { [string]$_.date })
    if (($historyDates -join '|') -ne (($historyDates | Sort-Object) -join '|')) { Add-Error "Genre history is not sorted ascending: $($entry.id)" }
    foreach ($event in $history) {
        Require-Value $event.date "$($entry.id).history.date"
        Require-Value $event.type "$($entry.id).history.type"
        Require-Value $event.summary "$($entry.id).history.summary"
        if ($event.diaryPath -and -not (Test-Path -LiteralPath (Join-Path $root ([string]$event.diaryPath)))) { Add-Error "Diary file not found: $($event.diaryPath)" }
    }

    for ($i = 0; $i -lt $items.Count; $i++) {
        $item = $items[$i]; $label = "$($entry.id).items[$i]"
        Require-Value $item.id "$label.id"; Require-Value $item.title "$label.title"; Require-Value $item.family "$label.family"
        Require-Value $item.curatorNote "$label.curatorNote"; Require-Value $item.sourceUrl "$label.sourceUrl"
        if (@($item.tags).Count -eq 0) { Add-Error "Item has no tags: $label" }
        $mediaType = if ($item.mediaType) { [string]$item.mediaType } elseif ($item.localImage) { 'image' } else { 'link' }
        if ($allowedMediaTypes -notcontains $mediaType) { Add-Error "Unsupported mediaType at $label`: $mediaType" }
        if (-not $item.license -and -not $item.rights) { Add-Error "Missing rights information: $label" }
        if ($item.sourceUrl) { Test-HttpUrl ([string]$item.sourceUrl) "$label.sourceUrl" }
        if ($seenIds.ContainsKey([string]$item.id)) { Add-Error "Specimen has multiple primary genres or duplicate id: $($item.id)" } else { $seenIds[[string]$item.id] = $entry.id }
        if ($seenSources.ContainsKey([string]$item.sourceUrl)) { Add-Error "Duplicate sourceUrl across genres: $($item.sourceUrl)" } else { $seenSources[[string]$item.sourceUrl] = $entry.id }
        $asset = if ($item.localAsset) { [string]$item.localAsset } else { [string]$item.localImage }
        if ($asset) { Test-Asset $asset "$label.localAsset"; if (-not $item.creator -and -not $item.artist) { Add-Error "Stored asset needs creator or artist: $label" } }
        if ($item.previewImage -and [string]$item.previewImage -ne $asset) { Test-Asset ([string]$item.previewImage) "$label.previewImage" }
        if ($mediaType -eq 'text' -and -not $item.textContent -and -not $item.excerpt -and -not $item.description) { Add-Error "Text item needs content or excerpt: $label" }
        if ($CheckLinks -and $item.sourceUrl -and ($All -or $entry.id -eq $Genre)) { Test-SourceLink ([string]$item.sourceUrl) }
    }
}

if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Output "ERROR $_" }; throw "Genre validation failed with $($errors.Count) error(s)" }
Write-Output "PASS genres=$($targets.Count) specimens=$($seenIds.Count) assets=$($seenAssets.Count) linksChecked=$($CheckLinks.IsPresent)"
