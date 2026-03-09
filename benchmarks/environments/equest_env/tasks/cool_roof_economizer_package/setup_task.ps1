# Setup script for cool_roof_economizer_package task.
# Imports the 4StoreyBuilding BDL model into eQUEST and records baseline state.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_cool_roof_economizer_package.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up cool_roof_economizer_package task ==="
    . C:\workspace\scripts\task_utils.ps1

    # Record task start time for anti-gaming timestamp checks
    $startTs = [int][double]::Parse((Get-Date -UFormat %s))
    Set-Content -Path "C:\Users\Docker\task_start_ts_cool_roof_economizer.txt" -Value $startTs
    Write-Host "Task start timestamp: $startTs"

    # Close any open eQUEST / DOE-2 processes
    Get-Process | Where-Object { $_.ProcessName -like "*quest*" -or $_.ProcessName -like "*doe*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Clean up previous project directory to avoid "project already exists" conflicts
    $projDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"
    if (Test-Path $projDir) { Remove-Item $projDir -Recurse -Force -ErrorAction SilentlyContinue }

    # Ensure result file from any previous run is removed
    $resultFile = "C:\Users\Docker\cool_roof_economizer_package_result.json"
    if (Test-Path $resultFile) { Remove-Item $resultFile -Force -ErrorAction SilentlyContinue }

    $inpFile = "C:\Users\Docker\Desktop\eQUEST_Projects\4StoreyBuilding.inp"
    Write-Host "Building model: $inpFile"

    # Record baseline state: verify .inp exists and capture key parameter values
    if (-not (Test-Path $inpFile)) {
        throw "4StoreyBuilding.inp not found at expected path: $inpFile"
    }
    $inpContent = Get-Content $inpFile -Raw
    # Record baseline ABSORPTANCE values (should be 0.6 in clean model)
    $ewallAbsMatch = [regex]::Match($inpContent,
        '"EWall Construction"\s*=\s*CONSTRUCTION[^.]*ABSORPTANCE\s*=\s*([\d.]+)',
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $baselineEwallAbs = if ($ewallAbsMatch.Success) { $ewallAbsMatch.Groups[1].Value } else { "unknown" }

    $roofAbsMatch = [regex]::Match($inpContent,
        '"Roof Construction"\s*=\s*CONSTRUCTION[^.]*ABSORPTANCE\s*=\s*([\d.]+)',
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $baselineRoofAbs = if ($roofAbsMatch.Success) { $roofAbsMatch.Groups[1].Value } else { "unknown" }

    Write-Host "Baseline EWall ABSORPTANCE: $baselineEwallAbs"
    Write-Host "Baseline Roof ABSORPTANCE: $baselineRoofAbs"
    Set-Content -Path "C:\Users\Docker\baseline_cool_roof_ewall_abs.txt" -Value $baselineEwallAbs
    Set-Content -Path "C:\Users\Docker\baseline_cool_roof_roof_abs.txt" -Value $baselineRoofAbs

    # Launch eQUEST
    $eqExe = Find-EqExe
    Launch-EqProjectInteractive -EqExe $eqExe -WaitSeconds 15

    Write-Host "Navigating startup dialog to import 4StoreyBuilding.inp..."
    $ErrorActionPreference = "Continue"

    # Click startup dialog title area, select "Open Existing", click OK
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

    # Dismiss "project already exists" dialog if it appears
    Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "enter"} | Out-Null
    Start-Sleep -Seconds 3

    # Confirm "Create Project from BDL File" dialog
    Invoke-PyAutoGUICommand -Command @{action = "click"; x = 735; y = 419} | Out-Null
    Write-Host "BDL import started — eQUEST may go Not Responding for 60-120 seconds (normal)."
    Start-Sleep -Seconds 90

    # Poll until eQUEST becomes responsive
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
    else { Write-Host "WARNING: eQUEST not found after setup." }

    Write-Host "=== cool_roof_economizer_package setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
