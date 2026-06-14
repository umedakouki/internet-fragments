param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$Date,

    [switch]$CheckLinks
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$collectionPath = Join-Path $root "data/collections/$Date.json"
$indexPath = Join-Path $root "data/collections/index.json"
$errors = New-Object System.Collections.Generic.List[string]

function Add-Error([string]$message) {
    $script:errors.Add($message)
}

function Require-Value([object]$value, [string]$label) {
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
        Add-Error "Missing value: $label"
    }
}

if (-not (Test-Path -LiteralPath $collectionPath)) {
    throw "Collection file not found: $collectionPath"
}
if (-not (Test-Path -LiteralPath $indexPath)) {
    throw "Index file not found: $indexPath"
}

$collection = Get-Content -Raw -Encoding UTF8 -LiteralPath $collectionPath | ConvertFrom-Json
$index = Get-Content -Raw -Encoding UTF8 -LiteralPath $indexPath | ConvertFrom-Json
$entries = @($index.collections | Where-Object { $_.date -eq $Date })
$items = @($collection.items)

if ($collection.date -ne $Date) { Add-Error "Collection date does not match file name" }
if ($items.Count -lt 10 -or $items.Count -gt 50) { Add-Error "Item count must be between 10 and 50: $($items.Count)" }
if ([int]$collection.itemCount -ne $items.Count) { Add-Error "itemCount does not match items length" }
if ($entries.Count -ne 1) { Add-Error "Index must contain exactly one entry for $Date" }

if ($entries.Count -eq 1) {
    $entry = $entries[0]
    if ([int]$entry.itemCount -ne $items.Count) { Add-Error "Index itemCount does not match collection" }
    if ($entry.path -ne "data/collections/$Date.json") { Add-Error "Index JSON path is incorrect" }
    if ($entry.diaryPath -ne "diary/$Date.md") { Add-Error "Index diary path is incorrect" }
    if (-not (Test-Path -LiteralPath (Join-Path $root $entry.diaryPath))) { Add-Error "Diary file does not exist" }
}

$dates = @($index.collections | ForEach-Object { $_.date })
$sortedDates = @($dates | Sort-Object)
if (($dates -join "`n") -ne ($sortedDates -join "`n")) { Add-Error "Index dates are not sorted ascending" }

$seenIds = @{}
$seenSources = @{}
$seenImages = @{}

for ($i = 0; $i -lt $items.Count; $i++) {
    $item = $items[$i]
    $label = "items[$i]"
    Require-Value $item.id "$label.id"
    Require-Value $item.title "$label.title"
    Require-Value $item.family "$label.family"
    Require-Value $item.curatorNote "$label.curatorNote"
    Require-Value $item.sourceUrl "$label.sourceUrl"

    if ($seenIds.ContainsKey([string]$item.id)) { Add-Error "Duplicate id: $($item.id)" } else { $seenIds[[string]$item.id] = $true }
    if ($seenSources.ContainsKey([string]$item.sourceUrl)) { Add-Error "Duplicate sourceUrl: $($item.sourceUrl)" } else { $seenSources[[string]$item.sourceUrl] = $true }

    if ($item.localImage) {
        $imagePath = [string]$item.localImage
        $expectedPrefix = "assets/collections/$Date/"
        if (-not $imagePath.StartsWith($expectedPrefix, [StringComparison]::Ordinal)) { Add-Error "Image path is outside date directory: $imagePath" }
        if ($imagePath.Contains('..')) { Add-Error "Image path contains traversal: $imagePath" }
        if (-not (Test-Path -LiteralPath (Join-Path $root $imagePath))) { Add-Error "Image file not found: $imagePath" }
        if ($seenImages.ContainsKey($imagePath)) { Add-Error "Duplicate localImage: $imagePath" } else { $seenImages[$imagePath] = $true }
        Require-Value $item.artist "$label.artist"
        Require-Value $item.license "$label.license"
    }

    if ($CheckLinks -and $item.sourceUrl) {
        $status = & curl.exe --ssl-no-revoke -L --head --silent --output NUL --write-out '%{http_code}' `
            --connect-timeout 10 --max-time 30 -A 'InternetFragmentsValidator/1.0' $item.sourceUrl
        if ($LASTEXITCODE -ne 0 -or $status -eq '403' -or $status -eq '405') {
            $status = & curl.exe --ssl-no-revoke -L --range 0-0 --silent --output NUL --write-out '%{http_code}' `
                --connect-timeout 10 --max-time 30 -A 'InternetFragmentsValidator/1.0' $item.sourceUrl
        }
        if ($LASTEXITCODE -ne 0 -or [int]$status -lt 200 -or [int]$status -ge 400) {
            Add-Error "Source link failed ($status): $($item.sourceUrl)"
        }
        Start-Sleep -Milliseconds 500
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Output "ERROR $_" }
    throw "Collection validation failed with $($errors.Count) error(s)"
}

Write-Output "PASS $Date items=$($items.Count) images=$($seenImages.Count) linksChecked=$($CheckLinks.IsPresent)"
