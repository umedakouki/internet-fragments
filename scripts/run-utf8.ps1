param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path
)

$ErrorActionPreference = "Stop"

$resolvedPath = (Resolve-Path -LiteralPath $Path).Path
$source = Get-Content -Raw -Encoding UTF8 -LiteralPath $resolvedPath
$script = [scriptblock]::Create($source)
$repoRoot = Split-Path -Parent (Split-Path -Parent $resolvedPath)

Push-Location $repoRoot
try {
    & $script
}
finally {
    Pop-Location
}
exit 0
