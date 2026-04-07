# Setup script for assess_inter_radicular_space task.
# Launches Blue Sky Plan with the mandible_case.bsp project file pre-loaded.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_assess_inter_radicular_space.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up assess_inter_radicular_space task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Close any open Blue Sky Plan instances
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Get-Process | Where-Object {
        $_.ProcessName -like "*BlueSky*" -or $_.ProcessName -like "*BSP*" -or $_.ProcessName -like "*nats-server*"
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP
    Start-Sleep -Seconds 2

    Remove-Item "C:\Users\Docker\AppData\Local\BlueSkyBio\Blue Sky Plan\crashinfo.log" -Force -ErrorAction SilentlyContinue

    # Verify project file
    $projectFile = "C:\workspace\data\mandible_case.bsp"
    if (Test-Path $projectFile) {
        Write-Host "Project file found: $projectFile"
    } else {
        Write-Host "WARNING: Project file not found at $projectFile"
    }

    try { Setup-MesaOpenGL } catch { Write-Host "WARNING: Setup-MesaOpenGL: $($_.Exception.Message)" }

    $bspExe = Find-BlueSkyPlanExe
    Write-Host "Launching Blue Sky Plan with $projectFile..."
    Launch-BlueSkyPlanWithFile -BSPExe $bspExe -FilePath $projectFile -WaitSeconds 30

    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Write-Host "Dismissing dialogs..."
        & $dismissScript
    }

    # Additional late-Edge cleanup
    Start-Sleep -Seconds 5
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $lateEdge = Get-Process -Name "msedge", "msedgewebview2" -ErrorAction SilentlyContinue
    if ($null -ne $lateEdge -and @($lateEdge).Count -gt 0) {
        $lateEdge | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        PyAutoGUI-Click -X 814 -Y 255
        Start-Sleep -Seconds 1
        Get-Process -Name "msedge", "msedgewebview2" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        PyAutoGUI-Click -X 322 -Y 104
        Start-Sleep -Seconds 1
    }
    $ErrorActionPreference = $prevEAP

    $bspProc = Get-Process | Where-Object {
        $_.ProcessName -like "*BlueSky*" -or $_.ProcessName -like "*BSP*" -or $_.ProcessName -like "*Launcher*"
    } | Select-Object -First 1
    if ($bspProc) { Write-Host "Blue Sky Plan is running (PID: $($bspProc.Id))" }
    else { Write-Host "WARNING: Blue Sky Plan process not found." }

    Write-Host "=== assess_inter_radicular_space task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
