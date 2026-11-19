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
        "$env:USERPROFILE\Downloads\Godot_v4.7.2-stable_win64_console.exe",
        "$env:USERPROFILE\Downloads\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Godot) { Write-Host "Godot console executable not found (-Godot)." -ForegroundColor Red; exit 2 }

$out = Join-Path $project "build\web-city"
New-Item -ItemType Directory -Force $out | Out-Null
Write-Host "== exporting Web City" -ForegroundColor Cyan
& $Godot --headless --path $project --export-release "Web City" (Join-Path $out "index.html")
if ($LASTEXITCODE -ne 0) { Write-Host "export failed" -ForegroundColor Red; exit 1 }

Write-Host "== copying city tiles" -ForegroundColor Cyan
# hi and lo: the tile meshes; meta: each detailed tile's paths, parking, trees, signs and
# shops (fetched with the tile, so they're not in index.pck)
$tileFiles = @()
foreach ($d in @(@("hi", "*.glb"), @("lo", "*.glb"), @("meta", "*.json"))) {
    $dst = Join-Path $out "city\$($d[0])"
    New-Item -ItemType Directory -Force $dst | Out-Null
    Copy-Item (Join-Path $project "proto3d\city\$($d[0])\$($d[1])") $dst -Force
    $tileFiles += Get-ChildItem (Join-Path $project "proto3d\city\$($d[0])") -Filter $d[1] -File
}

Write-Host "== offline cache (sw.js)" -ForegroundColor Cyan
# BUILD: this commit, so every update replaces the cached engine and game. TILES: a hash
# of the tile files' contents, so it only changes (and players only re-download the city)
# when the tiles were rebuilt.
$commit = (& git -C $project rev-parse --short HEAD 2>$null)
if (-not $commit) { $commit = "dev" }
if (& git -C $project status --porcelain --untracked-files=no 2>$null) { $commit += "-dirty" + (Get-Date -Format "yyyyMMddHHmm") }
$md5 = [Security.Cryptography.MD5]::Create()
$list = New-Object Text.StringBuilder
foreach ($f in ($tileFiles | Sort-Object FullName)) {
    $st = [IO.File]::OpenRead($f.FullName)
    try { $h = [BitConverter]::ToString($md5.ComputeHash($st)) } finally { $st.Dispose() }
    [void]$list.Append("$($f.Directory.Name)/$($f.Name) $h`n")
}
$tilesHash = ([BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($list.ToString()))) -replace "-", "").Substring(0, 12).ToLower()
$sw = [IO.File]::ReadAllText((Join-Path $project "web\sw.js"))
$sw = [regex]::Replace($sw, "const BUILD = '[^']*';", "const BUILD = '$commit';")
$sw = [regex]::Replace($sw, "const TILES = '[^']*';", "const TILES = 'tiles-$tilesHash';")
[IO.File]::WriteAllText((Join-Path $out "sw.js"), $sw, (New-Object Text.UTF8Encoding $false))
"  BUILD = $commit, TILES = tiles-$tilesHash"
if (-not (Select-String -Path (Join-Path $out "index.html") -Pattern "serviceWorker.register('sw.js')" -SimpleMatch -Quiet)) {
    Write-Host "index.html doesn't register sw.js (custom HTML shell missing?)" -ForegroundColor Red; exit 1
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
  AddOutputFilterByType DEFLATE text/html text/javascript application/javascript application/wasm application/octet-stream model/gltf-binary application/json
</IfModule>

<IfModule mod_headers.c>
  # the page, engine and game change with each update: always check for a new version
  <FilesMatch "\.(html|js|wasm|pck)$">
    Header set Cache-Control "no-cache"
  </FilesMatch>
  # city tiles and their metadata rarely change: let browsers keep them for a week
  <FilesMatch "\.(glb|json)$">
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
