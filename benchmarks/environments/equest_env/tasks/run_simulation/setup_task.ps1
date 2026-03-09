# Setup script for run_simulation task.
# Imports the 4StoreyBuilding BDL model into eQUEST.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_run_simulation.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up run_simulation task ==="
    . C:\workspace\scripts\task_utils.ps1

    Get-Process | Where-Object { $_.ProcessName -like "*quest*" -or $_.ProcessName -like "*doe*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $projDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"
    if (Test-Path $projDir) { Remove-Item $projDir -Recurse -Force -ErrorAction SilentlyContinue }

    $inpFile = "C:\Users\Docker\Desktop\eQUEST_Projects\4StoreyBuilding.inp"
    Write-Host "Building model: $inpFile"

    $eqExe = Find-EqExe
    Launch-EqProjectInteractive -EqExe $eqExe -WaitSeconds 15

    Write-Host "Navigating startup dialog..."
    $ErrorActionPreference = "Continue"

    Invoke-PyAutoGUICommand -Command @{action = "click"; x = 640; y = 234} | Out-Null
    Start-Sleep -Milliseconds 500
    Invoke-PyAutoGUICommand -Command @{action = "click"; x = 442; y = 331} | Out-Null
    Start-Sleep -Milliseconds 500
    Invoke-PyAutoGUICommand -Command @{action = "click"; x = 629; y = 422} | Out-Null
    Start-Sleep -Seconds 3

    Invoke-PyAutoGUICommand -Command @{action = "click"; x = 305; y = 434} | Out-Null
    Start-Sleep -Milliseconds 300
    Invoke-PyAutoGUICommand -Command @{action = "hotkey"; keys = @("ctrl", "a")} | Out-Null
    Start-Sleep -Milliseconds 200
    Invoke-PyAutoGUICommand -Command @{action = "write"; text = $inpFile} | Out-Null
    Start-Sleep -Milliseconds 500
    Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "enter"} | Out-Null
    Start-Sleep -Seconds 3

    # Handle "project already exists" dialog if it appears
    Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "enter"} | Out-Null
    Start-Sleep -Seconds 3

    Invoke-PyAutoGUICommand -Command @{action = "click"; x = 735; y = 419} | Out-Null
    Write-Host "BDL import started, waiting for completion..."
    Start-Sleep -Seconds 90

    # Poll for eQUEST to become responsive
    $timeout = 120
    $elapsed = 0
    while ($elapsed -lt $timeout) {
        $eqProc = Get-Process | Where-Object { $_.ProcessName -like "*quest*" -and $_.MainWindowTitle -ne "" } | Select-Object -First 1
        if ($eqProc -and $eqProc.MainWindowTitle -notlike "*Not Responding*") {
            Write-Host "eQUEST responsive: $($eqProc.MainWindowTitle)"
            break
        }
        Start-Sleep -Seconds 5
        $elapsed += 5
    }

    $ErrorActionPreference = "Stop"
    $eqProc = Get-Process | Where-Object { $_.ProcessName -like "*quest*" } | Select-Object -First 1
    if ($eqProc) { Write-Host "eQUEST running (PID: $($eqProc.Id))" }
    else { Write-Host "WARNING: eQUEST not found." }

    Write-Host "=== run_simulation task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
