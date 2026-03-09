# Setup script for middle_floor_comfort_roof_upgrade task.
# Imports the 4StoreyBuilding BDL model into eQUEST and records baseline state.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_middle_floor_comfort_roof.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up middle_floor_comfort_roof_upgrade task ==="
    . C:\workspace\scripts\task_utils.ps1

    # Record task start time
    $startTs = [int][double]::Parse((Get-Date -UFormat %s))
    Set-Content -Path "C:\Users\Docker\task_start_ts_middle_floor_roof.txt" -Value $startTs
    Write-Host "Task start timestamp: $startTs"

    # Close any open eQUEST / DOE-2 processes
    Get-Process | Where-Object { $_.ProcessName -like "*quest*" -or $_.ProcessName -like "*doe*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Clean up previous project directory
    $projDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"
    if (Test-Path $projDir) { Remove-Item $projDir -Recurse -Force -ErrorAction SilentlyContinue }

    $resultFile = "C:\Users\Docker\middle_floor_comfort_roof_upgrade_result.json"
    if (Test-Path $resultFile) { Remove-Item $resultFile -Force -ErrorAction SilentlyContinue }

    $inpFile = "C:\Users\Docker\Desktop\eQUEST_Projects\4StoreyBuilding.inp"
    Write-Host "Building model: $inpFile"

    if (-not (Test-Path $inpFile)) {
        throw "4StoreyBuilding.inp not found at: $inpFile"
    }

    # Record baseline: Roof ABSORPTANCE and a Middle Floor zone DESIGN-COOL-T
    $inpContent = Get-Content $inpFile -Raw
    $roofAbsMatch = [regex]::Match($inpContent,
        '"Roof Construction"\s*=\s*CONSTRUCTION[^.]*ABSORPTANCE\s*=\s*([\d.]+)',
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $baselineRoofAbs = if ($roofAbsMatch.Success) { $roofAbsMatch.Groups[1].Value } else { "unknown" }

    $midCoolTMatch = [regex]::Match($inpContent,
        '"South Perim Zn \(M\.S21\)"\s*=\s*ZONE[^.]*DESIGN-COOL-T\s*=\s*([\d.]+)',
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $baselineMidCoolT = if ($midCoolTMatch.Success) { $midCoolTMatch.Groups[1].Value } else { "unknown" }

    Write-Host "Baseline Roof ABSORPTANCE: $baselineRoofAbs"
    Write-Host "Baseline M.S21 DESIGN-COOL-T: $baselineMidCoolT"
    Set-Content -Path "C:\Users\Docker\baseline_mid_roof_abs.txt" -Value $baselineRoofAbs
    Set-Content -Path "C:\Users\Docker\baseline_mid_floor_cool_t.txt" -Value $baselineMidCoolT

    # Launch eQUEST
    $eqExe = Find-EqExe
    Launch-EqProjectInteractive -EqExe $eqExe -WaitSeconds 15

    Write-Host "Navigating startup dialog to import 4StoreyBuilding.inp..."
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

    Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "enter"} | Out-Null
    Start-Sleep -Seconds 3

    Invoke-PyAutoGUICommand -Command @{action = "click"; x = 735; y = 419} | Out-Null
    Write-Host "BDL import started — waiting up to 210 seconds for eQUEST to become responsive."
    Start-Sleep -Seconds 90

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

    Write-Host "=== middle_floor_comfort_roof_upgrade setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
