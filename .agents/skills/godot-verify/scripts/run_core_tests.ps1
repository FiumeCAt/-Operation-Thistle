param(
    [switch]$SkipImport,
    [string[]]$Tests,
    [string]$Godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe",
    [string]$Project = "D:\AI Game\HellWalker\HellWalker_DollProtocol",
    [int]$TimeoutSec = 180
)

$ErrorActionPreference = "Stop"

$DefaultCoreTests = @(
    "ads_test",
    "ai_alert_test",
    "armor_2d_test",
    "armory_2d_test",
    "backpack_2d_test",
    "bullet_speed_test",
    "codex_menu_test",
    "combat_system_test",
    "damage_model_test",
    "data_tables_test",
    "deco_containers_test",
    "deployment_2d_test",
    "enemy_attack_test",
    "feedback_system_test",
    "flow_2d_test",
    "fx_warmup_test",
    "game_units_test",
    "goliath_arena_test",
    "interaction_system_test",
    "loot_system_test",
    "map_2d_test",
    "menu_2d_test",
    "mod_install_service_test",
    "mods_2d_test",
    "navigation_2d_test",
    "new_enemies_2d_test",
    "player_bullet_test",
    "resources_2d_test",
    "run_events_hud_test",
    "save_slots_2d_test",
    "save_system_test",
    "settings_2d_test",
    "shoot_2d_test",
    "spread_accumulation_test",
    "spread_ballistics_model_test",
    "stage1_2d_test",
    "talents_2d_test",
    "vision_2d_test",
    "vision_fog_2d_test",
    "wall_edge_hit_test",
    "wave_system_test",
    "waves_2d_test",
    "weapon_m2_m4_test",
    "weapon_m3_test",
    "weapon_rig_test",
    "weapon_stats_model_test"
)

if (-not (Test-Path $Godot)) {
    Write-Error "Godot executable not found: $Godot"
    exit 2
}
if (-not (Test-Path $Project)) {
    Write-Error "Project directory not found: $Project"
    exit 2
}

$targetTests = if ($Tests -and $Tests.Count -gt 0) {
    $Tests | ForEach-Object { ($_ -split ',') } | ForEach-Object { $_.Trim() -replace '\.gd$', '' } | Where-Object { $_ -ne '' }
} else {
    $DefaultCoreTests
}

$logDir = Join-Path $Project "out\test_logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Read-LogText {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return "" }
    try {
        return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    } catch {
        return ""
    }
}

if (-not $SkipImport) {
    Write-Host "Running Godot --import..."
    $impOut = Join-Path $logDir "_import.stdout.log"
    $impErr = Join-Path $logDir "_import.stderr.log"
    $impProc = Start-Process -FilePath $Godot `
        -ArgumentList @('--headless', '--path', "`"$Project`"", '--import') `
        -NoNewWindow -PassThru `
        -RedirectStandardOutput $impOut `
        -RedirectStandardError $impErr
    if (-not $impProc.WaitForExit($TimeoutSec * 1000)) {
        try { $impProc.Kill() } catch {}
        $impProc.WaitForExit()
        Write-Error "Godot --import timed out after ${TimeoutSec}s. Logs: $logDir"
        exit 2
    }
    $impProc.WaitForExit()
    $impCombined = (Read-LogText $impOut) + "`n" + (Read-LogText $impErr)
    $impErrMatches = [regex]::Matches($impCombined, '(?m)^.*(SCRIPT ERROR|Parse Error|Could not find type).*$')
    if ($impErrMatches.Count -gt 0) {
        Write-Warning "Godot --import reported $($impErrMatches.Count) script/parse error line(s). Check $impOut / $impErr"
    } else {
        Write-Host "Godot --import completed cleanly."
    }
}

$summaryPattern = '(?i)(?:(\d+)\s*ok\s*/\s*(\d+)\s*fail|(\d+)\s*checks?,\s*(\d+)\s*fail)'
$failLinePattern = '(?m)^\s*FAIL\b'
$scriptErrPattern = '(?m)(SCRIPT ERROR|Parse Error|Could not find type)'

$results = New-Object System.Collections.Generic.List[object]

foreach ($t in $targetTests) {
    $scriptRel = "res://tests/$t.gd"
    $scriptFs = Join-Path $Project "tests\$t.gd"
    if (-not (Test-Path $scriptFs)) {
        $results.Add([PSCustomObject]@{
            Test    = $t
            Status  = "UNKNOWN"
            OK      = 0
            Fail    = 0
            Errors  = 1
            Seconds = 0.0
        })
        continue
    }

    $outLog = Join-Path $logDir "$t.stdout.log"
    $errLog = Join-Path $logDir "$t.stderr.log"
    if (Test-Path $outLog) { Remove-Item $outLog -Force -ErrorAction SilentlyContinue }
    if (Test-Path $errLog) { Remove-Item $errLog -Force -ErrorAction SilentlyContinue }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = Start-Process -FilePath $Godot `
        -ArgumentList @('--headless', '--path', "`"$Project`"", '--script', $scriptRel) `
        -NoNewWindow -PassThru `
        -RedirectStandardOutput $outLog `
        -RedirectStandardError $errLog

    $timedOut = $false
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        $timedOut = $true
        try { $proc.Kill() } catch {}
    }
    $proc.WaitForExit()
    $sw.Stop()
    $sec = [math]::Round($sw.Elapsed.TotalSeconds, 2)

    $combined = (Read-LogText $outLog) + "`n" + (Read-LogText $errLog)
    $matches = [regex]::Matches($combined, $summaryPattern)
    $failLines = ([regex]::Matches($combined, $failLinePattern)).Count
    $errLines = ([regex]::Matches($combined, $scriptErrPattern)).Count

    $hasSummary = $matches.Count -gt 0
    $okCount = 0
    $failCount = 0
    if ($hasSummary) {
        $m = $matches[$matches.Count - 1]
        if ($m.Groups[1].Success) {
            $okCount = [int]$m.Groups[1].Value
            $failCount = [int]$m.Groups[2].Value
        } else {
            $okCount = [int]$m.Groups[3].Value
            $failCount = [int]$m.Groups[4].Value
        }
    }

    $status = if ($timedOut) {
        "TIMEOUT"
    } elseif ($failCount -gt 0 -or $failLines -gt 0) {
        "FAIL"
    } elseif ($hasSummary -and $errLines -eq 0) {
        "PASS"
    } elseif ($hasSummary -and $errLines -gt 0) {
        "PASS*"
    } else {
        "UNKNOWN"
    }

    $results.Add([PSCustomObject]@{
        Test    = $t
        Status  = $status
        OK      = $okCount
        Fail    = [math]::Max($failCount, $failLines)
        Errors  = $errLines
        Seconds = $sec
    })
}

$results | Format-Table -AutoSize

$totalTests = $results.Count
$passCount = ($results | Where-Object { $_.Status -eq "PASS" }).Count
$passStarCount = ($results | Where-Object { $_.Status -eq "PASS*" }).Count
$failStatusCount = ($results | Where-Object { $_.Status -eq "FAIL" }).Count
$unknownCount = ($results | Where-Object { $_.Status -eq "UNKNOWN" }).Count
$timeoutCount = ($results | Where-Object { $_.Status -eq "TIMEOUT" }).Count
$sumOk = ($results | Measure-Object -Property OK -Sum).Sum
$sumFail = ($results | Measure-Object -Property Fail -Sum).Sum
$sumErrors = ($results | Measure-Object -Property Errors -Sum).Sum

Write-Host ("TOTALS: tests={0} | PASS={1} PASS*={2} FAIL={3} UNKNOWN={4} TIMEOUT={5} | OK={6} Fail={7} ScriptErrors={8}" -f `
    $totalTests, $passCount, $passStarCount, $failStatusCount, $unknownCount, $timeoutCount, $sumOk, $sumFail, $sumErrors)
Write-Host "Logs saved to: $logDir"

$bad = ($results | Where-Object { $_.Status -notin @("PASS", "PASS*") }).Count
if ($bad -gt 0) {
    exit 1
}
exit 0
