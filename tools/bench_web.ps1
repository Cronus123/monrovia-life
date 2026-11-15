<#
  Runs the browser benchmark (proto3d/game/web_bench.gd) as a first visit: serves
  build\web-city with tools\serve_web.py, opens it with ?bench=1 in a new Microsoft Edge
  window with a brand-new profile (empty download and shader caches), waits for the result
  the game sends back, prints it and closes that Edge window.

  Usage:  powershell -ExecutionPolicy Bypass -File tools\bench_web.ps1 [-Port 8070] [-Python <python.exe>]
#>
param(
    [int]$Port = 8070,
    [string]$Python = "C:\Program Files\Blender Foundation\Blender 5.3\5.3\python\bin\python.exe",
    [int]$TimeoutSec = 300
)
$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$work = Join-Path $project "build\bench"
New-Item -ItemType Directory -Force $work | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$log = Join-Path $work "serve-$stamp.log"
$profile = Join-Path $work "edge-profile-$stamp"
$server = Start-Process -FilePath $Python -ArgumentList @("-I", "`"$project\tools\serve_web.py`"", $Port) `
    -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2
$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
Start-Process -FilePath $edge -ArgumentList @("--user-data-dir=`"$profile`"", "--no-first-run",
    "--no-default-browser-check", "--window-position=20,20", "--window-size=1280,800",
    "--disable-backgrounding-occluded-windows", "--disable-renderer-backgrounding", "--disable-background-timer-throttling",
    "--new-window", "http://127.0.0.1:$Port/index.html?bench=1") | Out-Null
$t0 = Get-Date
$result = $null
while (((Get-Date) - $t0).TotalSeconds -lt $TimeoutSec -and -not $result) {
    Start-Sleep -Seconds 3
    $hit = Get-Content $log -ErrorAction SilentlyContinue | Where-Object { $_ -match 'GET /bench\?r=([^ ]+)' } | Select-Object -Last 1
    if ($hit -and $hit -match 'GET /bench\?r=([^ ]+)') { $result = [uri]::UnescapeDataString($Matches[1]) }
}
Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | Where-Object { $_.CommandLine -like "*edge-profile-$stamp*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Confirm:$false -ErrorAction SilentlyContinue }
Stop-Process -Id $server.Id -Confirm:$false -ErrorAction SilentlyContinue
if ($result) {
    $result | Out-File -Encoding utf8 (Join-Path $work "result-$stamp.json")
    "first visit, {0:N0} s wall clock" -f ((Get-Date) - $t0).TotalSeconds
    $result
} else {
    "no result within $TimeoutSec s (log: $log)"
    exit 1
}
