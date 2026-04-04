# Setup script for lshape_bb_floor_setpoint_rebalancing task.
# Imports the L_Shape BDL model into eQUEST and records baseline state.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_lshape_bb_floor_setpoint.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up lshape_bb_floor_setpoint_rebalancing task ==="
    . C:\workspace\scripts\task_utils.ps1

    # Record task start time
    $startTs = [int][double]::Parse((Get-Date -UFormat %s))
    Set-Content -Path "C:\Users\Docker\task_start_ts_lshape_bb_setpoint.txt" -Value $startTs
    Write-Host "Task start timestamp: $startTs"

    # Close any open eQUEST / DOE-2 processes
    Get-Process | Where-Object { $_.ProcessName -like "*quest*" -or $_.ProcessName -like "*doe*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Clean up previous L_Shape project
    $projDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\L_Shape"
    if (Test-Path $projDir) { Remove-Item $projDir -Recurse -Force -ErrorAction SilentlyContinue }

    $resultFile = "C:\Users\Docker\lshape_bb_floor_setpoint_rebalancing_result.json"
    if (Test-Path $resultFile) { Remove-Item $resultFile -Force -ErrorAction SilentlyContinue }

    $inpFile = "C:\Users\Docker\Desktop\eQUEST_Projects\L_Shape.inp"
    Write-Host "Building model: $inpFile"

    if (-not (Test-Path $inpFile)) {
        throw "L_Shape.inp not found at: $inpFile"
    }

    # Record baseline DESIGN-COOL-T for a BB zone as anti-gaming reference
    $inpContent = Get-Content $inpFile -Raw
    $coolTMatch = [regex]::Match($inpContent,
        '"South Perim Zn \(BB\.S1\)"\s*=\s*ZONE[^.]*DESIGN-COOL-T\s*=\s*([\d.]+)',
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $baselineCoolT = if ($coolTMatch.Success) { $coolTMatch.Groups[1].Value } else { "unknown" }
    Write-Host "Baseline BB.S1 DESIGN-COOL-T: $baselineCoolT"
    Set-Content -Path "C:\Users\Docker\baseline_lshape_bb_cool_t.txt" -Value $baselineCoolT

    # Launch eQUEST
    $eqExe = Find-EqExe
    Launch-EqProjectInteractive -EqExe $eqExe -WaitSeconds 15

    Write-Host "Navigating startup dialog to import L_Shape.inp..."
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
    Write-Host "BDL import started — L_Shape is 127 KB, waiting 120 seconds for eQUEST to process."
    Start-Sleep -Seconds 120

    $timeout = 180
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

    Write-Host "=== lshape_bb_floor_setpoint_rebalancing setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
