# setup_task.ps1 — water_treatment_scada_tags
# Opens Crimson 3.0 with a blank project and lays out reference files in Notepad.
# Order: CLEAN → RECORD → SEED → LAUNCH (per Universal Ordering Rule)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_water_treatment.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up water_treatment_scada_tags task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # --- CLEAN: kill any running applications ---
    Kill-AllCrimson
    Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # --- SEED: ensure reference data files are on Desktop ---
    $tasksDir = "C:\Users\Docker\Desktop\CrimsonTasks"
    New-Item -ItemType Directory -Force -Path $tasksDir | Out-Null

    $projDir = "C:\Users\Docker\Documents\CrimsonProjects"
    New-Item -ItemType Directory -Force -Path $projDir | Out-Null

    $filesToCopy = @(
        "water_treatment_tag_register.csv",
        "who_water_quality_standards.txt"
    )
    foreach ($f in $filesToCopy) {
        $src = "C:\workspace\data\$f"
        $dst = "$tasksDir\$f"
        if (Test-Path $src) {
            Copy-Item $src -Destination $dst -Force
            Write-Host "Copied: $f → $tasksDir"
        } else {
            Write-Host "WARNING: Source file not found: $src"
        }
    }

    # --- RECORD: save task start timestamp for delta detection ---
    $taskStartTs = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $taskStartTs | Out-File "C:\Users\Docker\task_start_ts_water_treatment.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp recorded: $taskStartTs"

    # --- LAUNCH: start Crimson and open reference files ---
    $crimsonExe = Find-CrimsonExe
    Write-Host "Crimson executable: $crimsonExe"

    # Launch Crimson first (new blank project), then Notepad on top
    Write-Host "Launching Crimson (blank project)..."
    Launch-CrimsonInteractive -CrimsonExe $crimsonExe -WaitSeconds 15

    $crimsonProc = Wait-ForCrimsonProcess -TimeoutSeconds 30
    if ($crimsonProc) {
        Write-Host "Crimson running (PID: $($crimsonProc.Id))"
    } else {
        Write-Host "WARNING: Crimson process not found after launch."
    }

    # Dismiss registration / startup dialogs
    Write-Host "Dismissing startup dialogs..."
    try {
        Dismiss-CrimsonDialogsBestEffort -Retries 3 -InitialWaitSeconds 8 -BetweenRetriesSeconds 3
        Write-Host "Dialog dismissal complete."
    } catch {
        Write-Host "WARNING: Dialog dismissal: $($_.Exception.Message)"
    }

    # Navigate Crimson to Data Tags section so agent sees it immediately
    Start-Sleep -Seconds 2
    try {
        Invoke-PyAutoGUICommand -Command @{action = "click"; x = 71; y = 467} | Out-Null
        Start-Sleep -Seconds 1
        Write-Host "Clicked Data Tags in Navigation Pane."
    } catch {
        Write-Host "WARNING: Could not click Data Tags: $($_.Exception.Message)"
    }

    # Open BOTH reference files in separate Notepad windows (standards on top)
    # File 1: tag register
    $notepadScript1 = "C:\Windows\Temp\launch_notepad_wt1.cmd"
    $f1 = "$tasksDir\water_treatment_tag_register.csv"
    [System.IO.File]::WriteAllText($notepadScript1, "@echo off`r`nstart `"`" notepad.exe `"$f1`"")
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $t1 = (Get-Date).AddMinutes(1).ToString("HH:mm")
    schtasks /Create /TN "LaunchNotepad_WT1" /TR "cmd /c $notepadScript1" /SC ONCE /ST $t1 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN "LaunchNotepad_WT1" 2>$null
    Start-Sleep -Seconds 4
    schtasks /Delete /TN "LaunchNotepad_WT1" /F 2>$null
    Remove-Item $notepadScript1 -Force -ErrorAction SilentlyContinue

    # File 2: WHO standards (opens on top so agent reads it first)
    $notepadScript2 = "C:\Windows\Temp\launch_notepad_wt2.cmd"
    $f2 = "$tasksDir\who_water_quality_standards.txt"
    [System.IO.File]::WriteAllText($notepadScript2, "@echo off`r`nstart `"`" notepad.exe `"$f2`"")
    $t2 = (Get-Date).AddMinutes(1).ToString("HH:mm")
    schtasks /Create /TN "LaunchNotepad_WT2" /TR "cmd /c $notepadScript2" /SC ONCE /ST $t2 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN "LaunchNotepad_WT2" 2>$null
    Start-Sleep -Seconds 4
    schtasks /Delete /TN "LaunchNotepad_WT2" /F 2>$null
    Remove-Item $notepadScript2 -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP

    Write-Host "Both reference files opened in Notepad."
    Write-Host "=== water_treatment_scada_tags setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
