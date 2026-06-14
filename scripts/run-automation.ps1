param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')]
    [string]$Genre,
    [string]$CommitMessage = "Update $Genre collection",
    [string]$BaseUrl = 'https://umedakouki.github.io/internet-fragments/',
    [switch]$Publish
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) { $ghPath = $gh.Source } else { $ghPath = Join-Path $root '.tools/bin/gh.exe' }

function Invoke-Step([string]$label, [scriptblock]$action) {
    Write-Host "`n== $label ==" -ForegroundColor Cyan
    & $action
    if ($LASTEXITCODE -ne 0) { throw "$label failed with exit code $LASTEXITCODE." }
}

Push-Location $root
try {
    $branch = (& git branch --show-current).Trim()
    if ($branch -ne 'main') { throw "Automation must run on main, current branch is $branch." }
    if (-not (Test-Path -LiteralPath "data/genres/$Genre.json")) { throw "Genre file was not found: $Genre" }

    Write-Host 'Preflight status:'
    & git status --short --branch
    Invoke-Step 'Diff integrity' { & git diff --check }
    Invoke-Step 'All genre data' { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/validate-genre.ps1 -All }
    Invoke-Step 'Source links' { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/validate-genre.ps1 -Genre $Genre -CheckLinks }
    Invoke-Step 'Local browser' { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-site.ps1 -Genre $Genre }

    if (-not $Publish) {
        Write-Host "Validation complete. Re-run with -Publish to commit, push, and verify Pages."
        exit 0
    }

    if (-not (Test-Path -LiteralPath $ghPath)) { throw 'GitHub CLI was not found in PATH or .tools/bin/gh.exe.' }
    Invoke-Step 'Stage changes' { & git add -A }
    $staged = & git diff --cached --name-only
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect staged changes.' }
    if ($staged) {
        Invoke-Step 'Commit changes' { & git commit -m $CommitMessage }
    } else {
        Write-Host 'No new changes to commit.'
    }
    Invoke-Step 'Push main' { & git push origin main }

    $commit = (& git rev-parse HEAD).Trim()
    $pagesSucceeded = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        $json = & $ghPath run list --commit $commit --limit 20 --json status,conclusion,workflowName,databaseId 2>$null
        if ($LASTEXITCODE -eq 0 -and $json) {
            $runs = $json | ConvertFrom-Json
            $pages = @($runs | Where-Object { $_.workflowName -match 'Pages' }) | Select-Object -First 1
            if ($pages -and $pages.status -eq 'completed') {
                if ($pages.conclusion -ne 'success') { throw "Pages run $($pages.databaseId) ended with $($pages.conclusion)." }
                Write-Host "Pages run $($pages.databaseId) succeeded."
                $pagesSucceeded = $true
                break
            }
        }
        Start-Sleep -Seconds 10
    }
    if (-not $pagesSucceeded) { throw 'Pages did not complete within five minutes. Re-run verify-pages.ps1 after deployment finishes.' }

    $verified = $false
    for ($attempt = 0; $attempt -lt 12; $attempt++) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-pages.ps1 -Genre $Genre -BaseUrl $BaseUrl
        if ($LASTEXITCODE -eq 0) { $verified = $true; break }
        Start-Sleep -Seconds 10
    }
    if (-not $verified) { throw 'Published Pages verification did not pass after deployment.' }
    Invoke-Step 'Final worktree' { & git diff --check; & git status --short --branch }
} finally {
    Pop-Location
}
