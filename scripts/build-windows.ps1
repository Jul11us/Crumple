param([ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64')
$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    # Assets/en.json is checked in; refresh it when Python is around.
    if (Get-Command python -ErrorAction SilentlyContinue) { python scripts/windows-strings.py; if ($LASTEXITCODE) { exit $LASTEXITCODE } }
    dotnet run --project Windows/Crumple.Core.Tests -c Release
    if ($LASTEXITCODE -ne 0) { throw 'Core tests failed.' }
    $out = Join-Path $root "build/windows/$Runtime"
    $release = Join-Path $root 'build/releases/windows'
    New-Item -ItemType Directory -Force $out, $release | Out-Null
    dotnet publish Windows/Crumple.Desktop/Crumple.Desktop.csproj -c Release -r $Runtime -o $out
    if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }
    $name = 'Crumple-1.2.0-Windows-' + $Runtime.Substring(4)
    Copy-Item "$out/Crumple.exe" "$release/$name.exe"
    Copy-Item Windows/installer/README.txt "$release/README.txt"
    Copy-Item Windows/THIRD-PARTY-NOTICES.txt "$release/THIRD-PARTY-NOTICES.txt"
    $makensis = (Get-Command makensis -ErrorAction SilentlyContinue).Source
    if (!$makensis) {
        $candidate = "${env:ProgramFiles(x86)}/NSIS/makensis.exe"
        if (Test-Path $candidate) { $makensis = $candidate }
    }
    if ($makensis -and $Runtime -eq 'win-x64') {
        & $makensis /V2 "/DAPP_EXE=$out/Crumple.exe" "/DOUTPUT_FILE=$release/$name-Setup.exe" "/DNOTICES=$release/THIRD-PARTY-NOTICES.txt" Windows/installer/Crumple.nsi
        if ($LASTEXITCODE -ne 0) { throw 'Installer packaging failed.' }
    }
    $checksums = Get-ChildItem "$release/Crumple-*.exe" | Sort-Object Name | ForEach-Object {
        $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $($_.Name)"
    }
    $checksums | Set-Content "$release/SHA256SUMS.txt" -Encoding ASCII
    Write-Host "Built: $release"
} finally { Pop-Location }
