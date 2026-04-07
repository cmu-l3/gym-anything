# Setup script for top_floor_atrium_skylight_addition task.
# Imports the 4StoreyBuilding BDL model into eQUEST.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_top_floor_atrium_skylight_addition.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up top_floor_atrium_skylight_addition task ==="
    . C:\workspace\scripts\task_utils.ps1

    # Close any open eQUEST / DOE-2 processes
    Get-Process | Where-Object { $_.ProcessName -like "*quest*" -or $_.ProcessName -like "*doe*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Clean up previous project directory to avoid "project already exists" conflicts
    $projDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"
    if (Test-Path $projDir) { Remove-Item $projDir -Recurse -Force -ErrorAction SilentlyContinue }

    $inpFile = "C:\Users\Docker\Desktop\eQUEST_Projects\4StoreyBuilding.inp"
    Write-Host "Building model: $inpFile"

    # Launch eQUEST
    $eqExe = Find-EqExe
    Launch-EqProjectInteractive -EqExe $eqExe -WaitSeconds 15

    Write-Host "Navigating startup dialog to import 4StoreyBuilding.inp..."
    $ErrorActionPreference = "Continue"

    # Focus dialog title bar, select "Open existing", click OK
    Invoke-PyAutoGUICommand -Command @{action = "click"; x = 640; y = 234} | Out-Null
    Start-Sleep -Milliseconds 500
    Invoke-PyAutoGUICommand -Command @{action = "click"; x = 442; y = 331} | Out-Null
    Start-Sleep -Milliseconds 500
    Invoke-PyAutoGUICommand -Command @{action = "click"; x = 629; y = 422} | Out-Null
    Start-Sleep -Seconds 3

    # Type .inp path in file browser
    Invoke-PyAutoGUICommand -Command @{action = "click"; x = 305; y = 434} | Out-Null
    Start-Sleep -Milliseconds 300
    Invoke-PyAutoGUICommand -Command @{action = "hotkey"; keys = @("ctrl", "a")} | Out-Null
    Start-Sleep -Milliseconds 200
    Invoke-PyAutoGUICommand -Command @{action = "write"; text = $inpFile} | Out-Null
    Start-Sleep -Milliseconds 500
    Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "enter"} | Out-Null
    Start-Sleep -Seconds 3

    # Handle "project already exists" dialog if it appears (press Enter = OK)
    Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "enter"} | Out-Null
    Start-Sleep -Seconds 3

    # OK on "Create Project from BDL File" dialog
    Invoke-PyAutoGUICommand -Command @{action = "click"; x = 735; y = 419} | Out-Null
    Write-Host "BDL import started, waiting for completion..."
    Start-Sleep -Seconds 90

    # Poll for eQUEST to become responsive (title drops "Not Responding")
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

    Write-Host "=== top_floor_atrium_skylight_addition task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
