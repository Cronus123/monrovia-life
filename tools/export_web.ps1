<#
  Monrovia Life: Streets - browser build.

  Exports the "Web City" preset to build\web-city\ (index.html, .js, .wasm, .pck: the game
  without the city tiles) and copies the city tiles next to it (build\web-city\city\hi and
  \lo, about 280 MB in 650 files), which the game downloads as the player moves.

  Upload the whole build\web-city folder to a static web host. The host must:
    - serve .wasm as application/wasm (all common hosts do)
    - allow files up to ~40 MB (the .wasm) and ~1300 files
    - no special headers needed (single-threaded build, no SharedArrayBuffer)
    - gzip/brotli compression and long cache times for city/*.glb are recommended

  Usage:  powershell -ExecutionPolicy Bypass -File tools\export_web.ps1 [-Godot <console exe>]
  Then test locally:  "<Blender>\5.3\python\bin\python.exe" -I tools\serve_web.py
#>
param(
    [string]$Godot = $env:GODOT
)
$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
if (-not $Godot) {
    $Godot = @(
        "$env:USERPROFILE\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
        "$env:USERPROFILE\Downloads\Godot_v4.7.2-stable_win64_console.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Godot) { Write-Host "Godot console executable not found (-Godot)." -ForegroundColor Red; exit 2 }

$out = Join-Path $project "build\web-city"
New-Item -ItemType Directory -Force $out | Out-Null
Write-Host "== exporting Web City" -ForegroundColor Cyan
& $Godot --headless --path $project --export-release "Web City" (Join-Path $out "index.html")
if ($LASTEXITCODE -ne 0) { Write-Host "export failed" -ForegroundColor Red; exit 1 }

Write-Host "== copying city tiles" -ForegroundColor Cyan
foreach ($lod in @("hi", "lo")) {
    $dst = Join-Path $out "city\$lod"
    New-Item -ItemType Directory -Force $dst | Out-Null
    Copy-Item (Join-Path $project "proto3d\city\$lod\*.glb") $dst -Force
}

Write-Host "== hosting files (GitHub Pages and Apache/IONOS)" -ForegroundColor Cyan
# GitHub Pages: serve play.libgamer.com, and don't run the folder through Jekyll
Set-Content -Path (Join-Path $out "CNAME") -Value "play.libgamer.com" -NoNewline -Encoding ascii
Set-Content -Path (Join-Path $out ".nojekyll") -Value "" -NoNewline -Encoding ascii
# Apache (IONOS and most shared hosts): wasm type, compression, caching
@'
# Monrovia Life: Streets - browser build (written by tools/export_web.ps1)
AddType application/wasm .wasm
AddType application/octet-stream .pck
AddType model/gltf-binary .glb

<IfModule mod_deflate.c>
  AddOutputFilterByType DEFLATE text/html text/javascript application/javascript application/wasm application/octet-stream model/gltf-binary
</IfModule>

<IfModule mod_headers.c>
  # the page, engine and game change with each update: always check for a new version
  <FilesMatch "\.(html|js|wasm|pck)$">
    Header set Cache-Control "no-cache"
  </FilesMatch>
  # city tiles rarely change: let browsers keep them for a week
  <FilesMatch "\.glb$">
    Header set Cache-Control "public, max-age=604800"
  </FilesMatch>
</IfModule>
'@ | Set-Content -Path (Join-Path $out ".htaccess") -Encoding ascii

$big = Get-ChildItem $out -Recurse -File | Where-Object { $_.Length -ge 100MB }
if ($big) { Write-Host "files over 100 MB (GitHub's limit): $($big.Name -join ', ')" -ForegroundColor Red; exit 1 }

$files = Get-ChildItem $out -Recurse -File
$core = $files | Where-Object { $_.DirectoryName -eq $out }
"{0} files, {1:N1} MB total; first download (page + engine + game): {2:N1} MB" -f $files.Count,
    (($files | Measure-Object Length -Sum).Sum / 1MB), (($core | Measure-Object Length -Sum).Sum / 1MB)
$core | Sort-Object Length -Descending | ForEach-Object { "  {0,8:N1} MB  {1}" -f ($_.Length / 1MB), $_.Name }
