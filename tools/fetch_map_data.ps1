<#
  Downloads the OpenStreetMap and elevation data for the 1:1 central Monrovia map.
  Runs tools/fetch_map_data.py with Blender's bundled Python (its OpenSSL can reach the
  Overpass API; Windows PowerShell 5.1's TLS stack cannot).
  Usage:  powershell -ExecutionPolicy Bypass -File tools\fetch_map_data.ps1
#>
$ErrorActionPreference = "Stop"
$py = Get-ChildItem "$env:ProgramFiles\Blender Foundation" -Recurse -Filter python.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match "\\python\\bin\\python.exe$" } | Select-Object -First 1 -ExpandProperty FullName
if (-not $py) { Write-Host "Blender's Python not found; run tools\fetch_map_data.py with any Python 3." -ForegroundColor Red; exit 2 }
& $py -I (Join-Path $PSScriptRoot "fetch_map_data.py")
exit $LASTEXITCODE
