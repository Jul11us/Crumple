param([string]$Executable = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build/releases/windows/Crumple-1.1.1-Windows-x64.exe'))
$ErrorActionPreference = 'Stop'
# Runs the real exe offscreen in demo mode: scans, a smart clean, a throw by hand into the basket,
# and screenshots of every page in all three themes. Only a new demo folder is touched.
$exe = (Resolve-Path $Executable).Path
$out = Join-Path (Split-Path -Parent $exe) 'Crumple-previews'
$demo = Join-Path $env:TEMP ('Crumple-Demo-' + [guid]::NewGuid().ToString('N'))
Remove-Item $out -Recurse -ErrorAction SilentlyContinue
$log = Join-Path (Split-Path -Parent $exe) 'Crumple-render.log'
$process = Start-Process $exe -ArgumentList @('--render', "`"$out`"", '--demo-home', "`"$demo`"", '--states') -PassThru -RedirectStandardOutput $log
if (!$process.WaitForExit(300000)) { $process.Kill(); throw 'Windows render test timed out.' }
Get-Content $log | Write-Host
if ($process.ExitCode -ne 0) { throw 'Windows render test failed.' }
if (!(Select-String -Path $log -Pattern 'landed in the bin' -Quiet)) { throw 'The paper thrown by hand did not reach the bin.' }
Write-Host "Screenshots: $out"
