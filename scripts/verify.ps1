$ErrorActionPreference = 'Stop'

$flutter = Get-Command flutter -ErrorAction Stop
$root = Split-Path -Parent $PSScriptRoot
$targets = @(
    'packages/core',
    'packages/database',
    'packages/player',
    'packages/sync_protocol',
    'apps/windows_app',
    'apps/android_app'
)

foreach ($target in $targets) {
    $path = Join-Path $root $target
    Write-Host "`n=== $target ===" -ForegroundColor Cyan
    Push-Location $path
    try {
        & $flutter.Source pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed: $target" }

        & $flutter.Source analyze
        if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed: $target" }

        & $flutter.Source test
        if ($LASTEXITCODE -ne 0) { throw "flutter test failed: $target" }
    }
    finally {
        Pop-Location
    }
}

Write-Host "`nAll project checks passed." -ForegroundColor Green
