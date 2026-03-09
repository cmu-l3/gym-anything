# Setup script for lshape_lighting_power_density_reduction task.
# Imports the L_Shape BDL model into eQUEST and records baseline lighting state.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_lshape_lighting_lpd.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up lshape_lighting_power_density_reduction task ==="
    . C:\workspace\scripts\task_utils.ps1

    # Record task start time
    $startTs = [int][double]::Parse((Get-Date -UFormat %s))
    Set-Content -Path "C:\Users\Docker\task_start_ts_lshape_lpd.txt" -Value $startTs
    Write-Host "Task start timestamp: $startTs"

    # Close any open eQUEST / DOE-2 processes
    Get-Process | Where-Object { $_.ProcessName -like "*quest*" -or $_.ProcessName -like "*doe*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Clean up previous L_Shape project
    $projDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\L_Shape"
    if (Test-Path $projDir) { Remove-Item $projDir -Recurse -Force -ErrorAction SilentlyContinue }

    $resultFile = "C:\Users\Docker\lshape_lighting_power_density_reduction_result.json"
    if (Test-Path $resultFile) { Remove-Item $resultFile -Force -ErrorAction SilentlyContinue }

    $inpFile = "C:\Users\Docker\Desktop\eQUEST_Projects\L_Shape.inp"
    Write-Host "Building model: $inpFile"

    if (-not (Test-Path $inpFile)) {
        throw "L_Shape.inp not found at: $inpFile"
    }

    # Record baseline: count spaces with LIGHTING-W/AREA = 1.3 (anti-gaming)
    $inpContent = Get-Content $inpFile -Raw
    $lpdMatches = [regex]::Matches($inpContent, 'LIGHTING-W/AREA\s*=\s*1\.3\b')
    $baselineLPDCount = $lpdMatches.Count
    Write-Host "Baseline count of LIGHTING-W/AREA = 1.3 occurrences: $baselineLPDCount"
    Set-Content -Path "C:\Users\Docker\baseline_lshape_lpd_count.txt" -Value $baselineLPDCount

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
    Write-Host "BDL import started — L_Shape is 127 KB, waiting 120 seconds."
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

    Write-Host "=== lshape_lighting_power_density_reduction setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
