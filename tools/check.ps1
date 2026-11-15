<#
  Monrovia Life: Streets - project health check.

  Runs, in order:
    1. Godot import            (--headless --import)
    2. Boot / parse check      (--headless --quit-after 300)
    3. Gameplay smoke test     (tests/smoke_test.gd)
    4. 3D prototype smoke test (tests/smoke_3d.gd)
    5. 1:1 city smoke test     (tests/smoke_city.gd; skipped if the city isn't generated)
    6. Game systems test       (tests/smoke_game.gd: economy, save, HUD, clock, traffic, cars,
                                weapons, shops, taxi, missions, police, arrest, hospital)
    7. Physics test            (tests/smoke_physics.gd: vehicle tuning, tyres, crash damage,
                                props, ragdolls, climbing, swimming)
    8. Big Talk storyline      (tests/smoke_bigtalk.gd: his five stages, jobs, grudges, endings, save)
    9. Weapons                 (tests/smoke_weapons.gd: wheel, magazines, reloads, auto fire, pellets,
                                melee and combos, shop, saves)
   10. Skills, perks, street life (tests/smoke_perks.gd)
   11. Leg animation          (tests/smoke_legs.gd: legs swing walking, sprinting, crouching,
                                aiming, uphill, over curbs; pedestrians too)
   12. Driving                (tests/smoke_drive.gd: every vehicle laps a test ground: top speed,
                                turns, a kerb hop, braking, reverse, handbrake slide recovery,
                                auto-right off the roof; runs on a fixed 60 fps clock)
   13. Playtest build         (tests/smoke_playtest.gd: title screen and menus, New Game, every
                                tutorial step, pause menu, F8 bug report; writes only to tests/output)
   14. Browser build          (tests/smoke_web.gd: city tiles streamed over HTTP like the browser
                                build, the Web City export preset, browser shaders, save import)
  and fails (exit code 1) if any step prints a script error, engine error or warning,
  or if the smoke test does not print "SMOKE TEST PASSED".

  Usage (from the project folder):
    powershell -ExecutionPolicy Bypass -File tools\check.ps1
    powershell -ExecutionPolicy Bypass -File tools\check.ps1 -Godot "D:\path\to\Godot_console.exe"
  Or set the GODOT environment variable to the console executable.
#>
param(
    [string]$Godot = $env:GODOT
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot

if (-not $Godot) {
    $candidates = @(
        "$env:USERPROFILE\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
        "$env:USERPROFILE\Downloads\Godot_v4.7.2-stable_win64_console.exe",
        "$env:ProgramFiles\Godot\Godot_v4.7.2-stable_win64_console.exe"
    )
    $Godot = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Godot -or -not (Test-Path $Godot)) {
    Write-Host "Godot console executable not found. Pass -Godot <path> or set `$env:GODOT." -ForegroundColor Red
    exit 2
}

$outDir = Join-Path $project "tests\output"
New-Item -ItemType Directory -Force $outDir | Out-Null

# Lines that count as failures. Godot prints these to stdout/stderr.
$bad = '(SCRIPT ERROR|^ERROR:|^WARNING:|Parse Error|Compile Error|SMOKE CHECK FAILED|SMOKE TEST FAILED|SMOKE3D CHECK FAILED|SMOKE3D TEST FAILED|SMOKECITY CHECK FAILED|SMOKECITY TEST FAILED|SMOKEGAME CHECK FAILED|SMOKEGAME TEST FAILED|SMOKEPHYS CHECK FAILED|SMOKEPHYS TEST FAILED|SMOKEBT CHECK FAILED|SMOKEBT TEST FAILED|SMOKEWPN CHECK FAILED|SMOKEWPN TEST FAILED|SMOKEPERKS CHECK FAILED|SMOKEPERKS TEST FAILED|SMOKELEGS CHECK FAILED|SMOKELEGS TEST FAILED|SMOKEDRIVE CHECK FAILED|SMOKEDRIVE TEST FAILED|SMOKEPLAY CHECK FAILED|SMOKEPLAY TEST FAILED|SMOKEWEB CHECK FAILED|SMOKEWEB TEST FAILED)'

# Engine messages that are not our bugs and recover by themselves. Jolt prints this one now
# and then when physics steps run back to back (seen with the old car code too); it waits
# for a free job slot and carries on.
$benign = "Jolt Physics job system exceeded the maximum number of jobs"

function Invoke-Step([string]$name, [string[]]$godotArgs, [string]$mustContain = "") {
    $log = Join-Path $outDir ("{0}.log" -f $name)
    Write-Host "== $name" -ForegroundColor Cyan
    $argLine = ($godotArgs | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join " "
    $p = Start-Process -FilePath $Godot -ArgumentList $argLine -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    $lines = @(Get-Content $log) + @(Get-Content "$log.err")
    $hits = $lines | Where-Object { $_ -match $bad -and $_ -notmatch $benign }
    $ok = $true
    if ($hits) {
        Write-Host "   FAILED - errors in output:" -ForegroundColor Red
        $hits | Select-Object -First 20 | ForEach-Object { Write-Host "   $_" }
        $ok = $false
    }
    if ($mustContain -and -not ($lines -match [regex]::Escape($mustContain))) {
        Write-Host "   FAILED - expected '$mustContain' in output" -ForegroundColor Red
        $ok = $false
    }
    if ($p.ExitCode -ne 0) {
        Write-Host "   FAILED - Godot exit code $($p.ExitCode)" -ForegroundColor Red
        $ok = $false
    }
    if ($ok) { Write-Host "   ok" -ForegroundColor Green }
    return $ok
}

$results = @(
    (Invoke-Step "1_import" @("--headless", "--path", $project, "--import")),
    (Invoke-Step "2_boot" @("--headless", "--path", $project, "--quit-after", "300")),
    (Invoke-Step "3_smoke" @("--headless", "--path", $project, "--script", "res://tests/smoke_test.gd") "SMOKE TEST PASSED"),
    (Invoke-Step "4_smoke_3d" @("--headless", "--path", $project, "--script", "res://tests/smoke_3d.gd") "SMOKE3D TEST PASSED"),
    (Invoke-Step "5_smoke_city" @("--headless", "--path", $project, "--script", "res://tests/smoke_city.gd") "SMOKECITY TEST PASSED"),
    (Invoke-Step "6_smoke_game" @("--headless", "--path", $project, "--script", "res://tests/smoke_game.gd") "SMOKEGAME TEST PASSED"),
    (Invoke-Step "7_smoke_physics" @("--headless", "--path", $project, "--script", "res://tests/smoke_physics.gd") "SMOKEPHYS TEST PASSED"),
    (Invoke-Step "8_smoke_bigtalk" @("--headless", "--path", $project, "--script", "res://tests/smoke_bigtalk.gd") "SMOKEBT TEST PASSED"),
    (Invoke-Step "9_smoke_weapons" @("--headless", "--path", $project, "--script", "res://tests/smoke_weapons.gd") "SMOKEWPN TEST PASSED"),
    (Invoke-Step "10_smoke_perks" @("--headless", "--path", $project, "--script", "res://tests/smoke_perks.gd") "SMOKEPERKS TEST PASSED"),
    (Invoke-Step "11_smoke_legs" @("--headless", "--path", $project, "--script", "res://tests/smoke_legs.gd") "SMOKELEGS TEST PASSED"),
    (Invoke-Step "12_smoke_drive" @("--headless", "--fixed-fps", "60", "--path", $project, "--script", "res://tests/smoke_drive.gd") "SMOKEDRIVE TEST PASSED"),
    (Invoke-Step "13_smoke_playtest" @("--headless", "--path", $project, "--script", "res://tests/smoke_playtest.gd") "SMOKEPLAY TEST PASSED"),
    (Invoke-Step "14_smoke_web" @("--headless", "--path", $project, "--script", "res://tests/smoke_web.gd") "SMOKEWEB TEST PASSED")
)

if ($results -contains $false) {
    Write-Host "CHECK FAILED (logs in $outDir)" -ForegroundColor Red
    exit 1
}
Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
exit 0
