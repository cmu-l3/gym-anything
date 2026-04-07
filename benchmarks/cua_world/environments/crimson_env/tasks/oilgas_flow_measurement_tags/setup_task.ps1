# setup_task.ps1 — oilgas_flow_measurement_tags
# Opens Crimson 3.0 with a blank project and lays out reference files in Notepad.
# Order: CLEAN → RECORD → SEED → LAUNCH

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_oilgas_flow.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up oilgas_flow_measurement_tags task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # --- CLEAN ---
    Kill-AllCrimson
    Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # --- SEED ---
    $tasksDir = "C:\Users\Docker\Desktop\CrimsonTasks"
    New-Item -ItemType Directory -Force -Path $tasksDir | Out-Null
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents\CrimsonProjects" | Out-Null

    foreach ($f in @("oilgas_wellsite_tag_register.csv", "aga3_measurement_parameters.txt")) {
        $src = "C:\workspace\data\$f"
        $dst = "$tasksDir\$f"
        if (Test-Path $src) {
            Copy-Item $src -Destination $dst -Force
            Write-Host "Copied: $f"
        } else {
            Write-Host "WARNING: Not found: $src"
        }
    }

    # --- RECORD ---
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File "C:\Users\Docker\task_start_ts_oilgas_flow.txt" -Encoding ASCII -Force
    Write-Host "Start timestamp: $ts"

    # --- LAUNCH ---
    $crimsonExe = Find-CrimsonExe
    Write-Host "Launching Crimson (blank project)..."
    Launch-CrimsonInteractive -CrimsonExe $crimsonExe -WaitSeconds 15
    Wait-ForCrimsonProcess -TimeoutSeconds 30 | Out-Null

    try {
        Dismiss-CrimsonDialogsBestEffort -Retries 3 -InitialWaitSeconds 8 -BetweenRetriesSeconds 3
    } catch {
        Write-Host "WARNING: Dialog dismissal: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds 2
    try {
        Invoke-PyAutoGUICommand -Command @{action = "click"; x = 71; y = 467} | Out-Null
        Start-Sleep -Seconds 1
    } catch {
        Write-Host "WARNING: Data Tags click: $($_.Exception.Message)"
    }

    # Open both reference files in Notepad
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    foreach ($pair in @(
        @("LaunchNotepad_OG1", "oilgas_wellsite_tag_register.csv"),
        @("LaunchNotepad_OG2", "aga3_measurement_parameters.txt")
    )) {
        $tn  = $pair[0]
        $fn  = $pair[1]
        $fp  = "$tasksDir\$fn"
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

    Write-Host "=== oilgas_flow_measurement_tags setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
