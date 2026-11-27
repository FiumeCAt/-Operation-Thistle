param(
    [switch]$SkipImport,
    [switch]$RealTime,
    [int]$Jobs = 0,
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
    "armory_subview_test",
    "backpack_2d_test",
    "bullet_speed_test",
    "codex_menu_test",
    "combat_system_test",
    "container_runtime_test",
    "damage_model_test",
    "data_tables_test",
    "deco_containers_test",
    "deployment_2d_test",
    "dodge_2d_test",
    "doll_rig_v2_test",
    "enemy_attack_test",
    "enemy_combat_test",
    "enemy_def_test",
    "enemy_perception_test",
    "feedback_system_test",
    "flow_2d_test",
    "fx_warmup_test",
    "game_units_test",
    "goliath_arena_test",
    "impact_audio_test",
    "interaction_system_test",
    "loot_system_test",
    "map_2d_test",
    "menu_2d_test",
    "mod_install_service_test",
    "mods_2d_test",
    "nav_grid_2d_test",
    "navigation_2d_test",
    "new_enemies_2d_test",
    "phase5b_debug_save_fps_test",
    "phase6a_progression_perception_test",
    "player_bullet_test",
    "progress_stores_test",
    "resources_2d_test",
    "run_events_hud_test",
    "save_slots_2d_test",
    "save_system_test",
    "scene_config_test",
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
    "weapon_feed_state_test",
    "weapon_m2_m4_test",
    "weapon_m3_test",
    "weapon_pose_ik_test",
    "weapon_rig_test",
    "weapon_stats_model_test",
    "weakspot_pseudo3d_test"
)

# Longest-Processing-Time (LPT) priority weights so heavy tests launch first and avoid tail stalls
$HeavyTestPriority = @{
    "mods_2d_test"                        = 100
    "weapon_m3_test"                      = 95
    "ads_test"                            = 90
    "shoot_2d_test"                       = 85
    "navigation_2d_test"                  = 80
    "wall_edge_hit_test"                  = 75
    "armory_2d_test"                      = 70
    "bullet_speed_test"                   = 65
    "stage1_2d_test"                      = 60
    "settings_2d_test"                    = 58
    "map_2d_test"                         = 56
    "weapon_rig_test"                     = 54
    "vision_2d_test"                      = 52
    "waves_2d_test"                       = 50
    "dodge_2d_test"                       = 48
    "deployment_2d_test"                  = 46
    "menu_2d_test"                        = 45
    "weapon_m2_m4_test"                   = 44
    "phase6a_progression_perception_test" = 42
    "talents_2d_test"                     = 40
    "new_enemies_2d_test"                 = 38
    "vision_fog_2d_test"                  = 36
    "weakspot_pseudo3d_test"              = 35
}

if (-not (Test-Path $Godot)) {
    Write-Error "Godot executable not found: $Godot"
    exit 2
}
if (-not (Test-Path $Project)) {
    Write-Error "Project directory not found: $Project"
    exit 2
}

$targetTests = @(if ($Tests -and $Tests.Count -gt 0) {
    $Tests | ForEach-Object { ($_ -split ',') } | ForEach-Object { $_.Trim() -replace '\.gd$', '' } | Where-Object { $_ -ne '' }
} else {
    $DefaultCoreTests
})

# Default concurrency: half of logical CPUs clamped to [2, 8] (sweet spot without thrashing disk/CPU)
$cpuCount = [Environment]::ProcessorCount
$effectiveJobs = if ($Jobs -gt 0) {
    [math]::Min($Jobs, [math]::Max(1, $targetTests.Count))
} else {
    $auto = [math]::Max(2, [math]::Min(8, [int][math]::Floor($cpuCount / 2)))
    [math]::Min($auto, [math]::Max(1, $targetTests.Count))
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

$wallSw = [System.Diagnostics.Stopwatch]::StartNew()
$importSec = 0.0

if (-not $SkipImport) {
    Write-Host "Running Godot --import..."
    $impSw = [System.Diagnostics.Stopwatch]::StartNew()
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
    $impSw.Stop()
    $importSec = [math]::Round($impSw.Elapsed.TotalSeconds, 2)
    $impCombined = (Read-LogText $impOut) + "`n" + (Read-LogText $impErr)
    $impErrMatches = @([regex]::Matches($impCombined, '(?m)^.*(SCRIPT ERROR|Parse Error|Could not find type).*$') |
        Where-Object { $_.Value -notmatch 'addons/phantom_camera' })
    if ($impErrMatches.Count -gt 0) {
        Write-Warning "Godot --import reported $($impErrMatches.Count) project script/parse error line(s). Check $impOut / $impErr"
        foreach ($em in $impErrMatches) { Write-Warning ("  " + $em.Value.Trim()) }
    } else {
        Write-Host ("Godot --import completed cleanly in {0}s." -f $importSec)
    }
}

$modeLabel = if ($RealTime) { "real-time" } else { "fixed-fps=60" }
Write-Host ("Running {0} tests (Jobs={1}, Mode={2})..." -f $targetTests.Count, $effectiveJobs, $modeLabel)

$summaryPattern = '(?i)(?:(\d+)\s*ok\s*/\s*(\d+)\s*fail|(\d+)\s*checks?,\s*(\d+)\s*fail)'
$failLinePattern = '(?m)^\s*FAIL\b'
$scriptErrPattern = '(?m)(SCRIPT ERROR|Parse Error|Could not find type)'

# Keep original display order index, but dispatch heaviest tests first (LPT scheduling)
$workQueue = New-Object System.Collections.Generic.Queue[object]
$indexed = for ($i = 0; $i -lt $targetTests.Count; $i++) {
    $name = $targetTests[$i]
    $prio = if ($HeavyTestPriority.ContainsKey($name)) { [int]$HeavyTestPriority[$name] } else { 10 }
    [PSCustomObject]@{ Index = $i; Name = $name; Priority = $prio }
}
foreach ($item in ($indexed | Sort-Object -Property @{Expression = "Priority"; Descending = $true}, @{Expression = "Index"; Ascending = $true})) {
    $workQueue.Enqueue($item)
}

$resultsByIndex = @{}
$active = New-Object System.Collections.Generic.List[object]

function Complete-TestJob {
    param([object]$Job, [bool]$TimedOut)

    $Job.Stopwatch.Stop()
    $sec = [math]::Round($Job.Stopwatch.Elapsed.TotalSeconds, 2)
    $exitCode = 0
    try { $exitCode = [int]$Job.Process.ExitCode } catch { $exitCode = -1 }

    $combined = (Read-LogText $Job.OutLog) + "`n" + (Read-LogText $Job.ErrLog)
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

    $status = if ($TimedOut) {
        "TIMEOUT"
    } elseif ($failCount -gt 0 -or $failLines -gt 0 -or $exitCode -ne 0) {
        "FAIL"
    } elseif ($hasSummary -and $errLines -eq 0) {
        "PASS"
    } elseif ($hasSummary -and $errLines -gt 0) {
        "PASS*"
    } else {
        "UNKNOWN"
    }

    return [PSCustomObject]@{
        Test     = $Job.Name
        Status   = $status
        OK       = $okCount
        Fail     = [math]::Max($failCount, $failLines)
        Errors   = $errLines
        ExitCode = $exitCode
        Seconds  = $sec
    }
}

while ($workQueue.Count -gt 0 -or $active.Count -gt 0) {
    # Fill available worker slots
    while ($workQueue.Count -gt 0 -and $active.Count -lt $effectiveJobs) {
        $item = $workQueue.Dequeue()
        $t = $item.Name
        $scriptRel = "res://tests/$t.gd"
        $scriptFs = Join-Path $Project "tests\$t.gd"
        if (-not (Test-Path $scriptFs)) {
            $resultsByIndex[$item.Index] = [PSCustomObject]@{
                Test     = $t
                Status   = "UNKNOWN"
                OK       = 0
                Fail     = 0
                Errors   = 1
                ExitCode = -1
                Seconds  = 0.0
            }
            continue
        }

        $outLog = Join-Path $logDir "$t.stdout.log"
        $errLog = Join-Path $logDir "$t.stderr.log"
        if (Test-Path $outLog) { Remove-Item $outLog -Force -ErrorAction SilentlyContinue }
        if (Test-Path $errLog) { Remove-Item $errLog -Force -ErrorAction SilentlyContinue }

        $godotArgs = New-Object System.Collections.Generic.List[string]
        $godotArgs.Add('--headless')
        if (-not $RealTime) {
            $godotArgs.Add('--fixed-fps')
            $godotArgs.Add('60')
        }
        $godotArgs.Add('--path')
        $godotArgs.Add("`"$Project`"")
        $godotArgs.Add('--script')
        $godotArgs.Add($scriptRel)

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $proc = Start-Process -FilePath $Godot `
            -ArgumentList $godotArgs.ToArray() `
            -NoNewWindow -PassThru `
            -RedirectStandardOutput $outLog `
            -RedirectStandardError $errLog

        $active.Add([PSCustomObject]@{
            Index     = $item.Index
            Name      = $t
            Process   = $proc
            Stopwatch = $sw
            OutLog    = $outLog
            ErrLog    = $errLog
        })
    }

    # Poll finished or timed-out workers
    for ($i = $active.Count - 1; $i -ge 0; $i--) {
        $job = $active[$i]
        if ($job.Process.HasExited) {
            $job.Process.WaitForExit()
            $resultsByIndex[$job.Index] = Complete-TestJob -Job $job -TimedOut $false
            $active.RemoveAt($i)
        } elseif ($job.Stopwatch.Elapsed.TotalSeconds -ge $TimeoutSec) {
            try { $job.Process.Kill() } catch {}
            try { $job.Process.WaitForExit(3000) | Out-Null } catch {}
            $resultsByIndex[$job.Index] = Complete-TestJob -Job $job -TimedOut $true
            $active.RemoveAt($i)
        }
    }

    if ($active.Count -gt 0) {
        Start-Sleep -Milliseconds 35
    }
}

$wallSw.Stop()
$wallSec = [math]::Round($wallSw.Elapsed.TotalSeconds, 2)

$results = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $targetTests.Count; $i++) {
    if ($resultsByIndex.ContainsKey($i)) {
        $results.Add($resultsByIndex[$i])
    }
}

$results | Format-Table Test, Status, OK, Fail, Errors, Seconds -AutoSize

$totalTests = $results.Count
$passCount = ($results | Where-Object { $_.Status -eq "PASS" }).Count
$passStarCount = ($results | Where-Object { $_.Status -eq "PASS*" }).Count
$failStatusCount = ($results | Where-Object { $_.Status -eq "FAIL" }).Count
$unknownCount = ($results | Where-Object { $_.Status -eq "UNKNOWN" }).Count
$timeoutCount = ($results | Where-Object { $_.Status -eq "TIMEOUT" }).Count
$sumOk = ($results | Measure-Object -Property OK -Sum).Sum
$sumFail = ($results | Measure-Object -Property Fail -Sum).Sum
$sumErrors = ($results | Measure-Object -Property Errors -Sum).Sum
$sumCpuSec = [math]::Round(($results | Measure-Object -Property Seconds -Sum).Sum, 2)
$testWallSec = [math]::Round([math]::Max(0.01, $wallSec - $importSec), 2)
$speedup = [math]::Round($sumCpuSec / $testWallSec, 2)

Write-Host ("TOTALS: tests={0} | PASS={1} PASS*={2} FAIL={3} UNKNOWN={4} TIMEOUT={5} | OK={6} Fail={7} ScriptErrors={8}" -f `
    $totalTests, $passCount, $passStarCount, $failStatusCount, $unknownCount, $timeoutCount, $sumOk, $sumFail, $sumErrors)
Write-Host ("TIMING: Wall={0}s (Import={1}s + Tests={2}s) | SumTestCpu={3}s | ParallelSpeedup={4}x | Jobs={5} Mode={6}" -f `
    $wallSec, $importSec, $testWallSec, $sumCpuSec, $speedup, $effectiveJobs, $modeLabel)
Write-Host "Logs saved to: $logDir"

# Strict quality gate: ONLY clean PASS (0 fail, 0 script errors, exit code 0) succeeds
$bad = ($results | Where-Object { $_.Status -ne "PASS" }).Count
if ($bad -gt 0) {
    Write-Host "FAILED / NON-CLEAN TESTS:"
    $results | Where-Object { $_.Status -ne "PASS" } | Format-Table Test, Status, OK, Fail, Errors, ExitCode, Seconds -AutoSize
    exit 1
}
exit 0
