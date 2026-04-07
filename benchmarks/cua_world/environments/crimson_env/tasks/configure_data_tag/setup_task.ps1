# Setup script for configure_data_tag task.
# Ensures Crimson is open with a new project and the reference data is visible.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_configure_data_tag.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up configure_data_tag task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) {
        throw "Missing task utils: $utils"
    }
    . $utils

    # Close any existing Crimson windows
    Kill-AllCrimson
    Start-Sleep -Seconds 2

    # Close any existing Notepad windows
    Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    # Ensure data files exist on Desktop
    $tasksDir = "C:\Users\Docker\Desktop\CrimsonTasks"
    New-Item -ItemType Directory -Force -Path $tasksDir | Out-Null

    $tagSpecFile = "$tasksDir\tag_specifications.csv"
    if (-not (Test-Path $tagSpecFile)) {
        Copy-Item "C:\workspace\data\tag_specifications.csv" -Destination $tagSpecFile -Force
    }

    $sensorDataFile = "$tasksDir\process_sensor_readings.csv"
    if (-not (Test-Path $sensorDataFile)) {
        Copy-Item "C:\workspace\data\process_sensor_readings.csv" -Destination $sensorDataFile -Force
    }
    Write-Host "Data files ready at: $tasksDir"

    # Find and launch Crimson FIRST (so Notepad opens on top of it)
    $crimsonExe = Find-CrimsonExe
    Write-Host "Crimson executable: $crimsonExe"
    Write-Host "Launching Crimson via scheduled task (interactive desktop)..."
    Launch-CrimsonInteractive -CrimsonExe $crimsonExe -WaitSeconds 15

    # Wait for Crimson to fully load
    $crimsonProc = Wait-ForCrimsonProcess -TimeoutSeconds 30
    if ($crimsonProc) {
        Write-Host "Crimson is running (PID: $($crimsonProc.Id))"
    } else {
        Write-Host "WARNING: Crimson process not found after launch."
    }

    # Dismiss any first-run dialogs (registration dialog appears on every launch)
    Write-Host "Dismissing any startup dialogs..."
    try {
        Dismiss-CrimsonDialogsBestEffort -Retries 3 -InitialWaitSeconds 8 -BetweenRetriesSeconds 3
        Write-Host "Dialog dismissal complete."
    } catch {
        Write-Host "WARNING: Dialog dismissal failed: $($_.Exception.Message)"
    }

    # Click on Data Tags in the Navigation Pane to show the Data Tags section
    Start-Sleep -Seconds 2
    try {
        Invoke-PyAutoGUICommand -Command @{action = "click"; x = 71; y = 467} | Out-Null
        Start-Sleep -Seconds 1
        Write-Host "Clicked Data Tags in Navigation Pane."
    } catch {
        Write-Host "WARNING: Could not click Data Tags: $($_.Exception.Message)"
    }

    # Now open Notepad AFTER Crimson so it appears on top for reference
    # This ensures the agent sees the CSV data first and knows it's available
    $notepadScript = "C:\Windows\Temp\launch_notepad.cmd"
    $notepadContent = "@echo off`r`nstart `"`" notepad.exe `"$tagSpecFile`""
    [System.IO.File]::WriteAllText($notepadScript, $notepadContent)

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
    schtasks /Create /TN "LaunchNotepad_GA" /TR "cmd /c $notepadScript" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN "LaunchNotepad_GA" 2>$null
    Start-Sleep -Seconds 5
    schtasks /Delete /TN "LaunchNotepad_GA" /F 2>$null
    Remove-Item $notepadScript -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP
    Write-Host "Notepad opened with tag_specifications.csv (on top of Crimson)"

    Write-Host "=== configure_data_tag task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
