# setup_task.ps1 — boiler_drum_3element_control
# CLEAN → DELETE STALE → SEED → RECORD → LAUNCH

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_boiler_drum.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up boiler_drum_3element_control task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # ── CLEAN ──────────────────────────────────────────────────────
    Kill-AllCrimson
    Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # ── SEED ───────────────────────────────────────────────────────
    $tasksDir = "C:\Users\Docker\Desktop\CrimsonTasks"
    $projectsDir = "C:\Users\Docker\Documents\CrimsonProjects"
    New-Item -ItemType Directory -Force -Path $tasksDir | Out-Null
    New-Item -ItemType Directory -Force -Path $projectsDir | Out-Null

    foreach ($f in @("boiler_instrument_schedule.csv", "asme_ptc4_control_narrative.txt")) {
        $src = "C:\workspace\data\$f"
        if (Test-Path $src) {
            Copy-Item $src -Destination "$tasksDir\$f" -Force
            Write-Host "Copied: $f"
        } else {
            Write-Host "WARNING: Not found: $src"
        }
    }

    # ── DELETE STALE OUTPUTS (before recording timestamp) ──────────
    $staleFiles = @(
        "$tasksDir\boiler_drum_result.json",
        "$tasksDir\boiler_drum_tags_export.csv",
        "$projectsDir\boiler_drum_3element.c3"
    )
    foreach ($sf in $staleFiles) {
        if (Test-Path $sf) {
            Remove-Item $sf -Force -ErrorAction SilentlyContinue
            Write-Host "Removed stale: $sf"
        }
    }

    # ── RECORD ─────────────────────────────────────────────────────
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File "C:\Users\Docker\task_start_ts_boiler_drum.txt" -Encoding ASCII -Force

    # ── LAUNCH ─────────────────────────────────────────────────────
    $crimsonExe = Find-CrimsonExe
    Launch-CrimsonInteractive -CrimsonExe $crimsonExe -WaitSeconds 15
    Wait-ForCrimsonProcess -TimeoutSeconds 30 | Out-Null

    try {
        Dismiss-CrimsonDialogsBestEffort -Retries 3 -InitialWaitSeconds 8 -BetweenRetriesSeconds 3
    } catch {
        Write-Host "WARNING: Dialog dismissal: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds 2

    # Navigate to Data Tags section
    try {
        Invoke-PyAutoGUICommand -Command @{action = "click"; x = 71; y = 467} | Out-Null
        Start-Sleep -Seconds 1
    } catch {
        Write-Host "WARNING: Data Tags click: $($_.Exception.Message)"
    }

    # ── OPEN REFERENCE FILES IN NOTEPAD ────────────────────────────
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    foreach ($pair in @(
        @("LaunchNotepad_BD1", "boiler_instrument_schedule.csv"),
        @("LaunchNotepad_BD2", "asme_ptc4_control_narrative.txt")
    )) {
        $tn = $pair[0]; $fn = $pair[1]; $fp = "$tasksDir\$fn"
        $scr = "C:\Windows\Temp\launch_$tn.cmd"
        [System.IO.File]::WriteAllText($scr, "@echo off`r`nstart `"`" notepad.exe `"$fp`"")
        $st = (Get-Date).AddMinutes(1).ToString("HH:mm")
        schtasks /Create /TN $tn /TR "cmd /c $scr" /SC ONCE /ST $st /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $tn 2>$null
        Start-Sleep -Seconds 4
        schtasks /Delete /TN $tn /F 2>$null
        Remove-Item $scr -Force -ErrorAction SilentlyContinue
    }
    $ErrorActionPreference = $prevEAP

    Write-Host "=== boiler_drum_3element_control setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
