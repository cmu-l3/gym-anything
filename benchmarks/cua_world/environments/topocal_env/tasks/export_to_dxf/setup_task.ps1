###############################################################################
# setup_task.ps1 — pre_task hook for export_to_dxf
# Launches TopoCal with survey points pre-loaded from denver_survey.top
###############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_export_to_dxf.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Setting up export_to_dxf task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    $edgeKiller = Start-EdgeKillerTask
    Close-Browsers

    Ensure-HTTPServer
    Ensure-PyAutoGUIServer

    # Open the pre-saved project with imported survey points
    $topFile = "C:\Users\Docker\Desktop\SurveyData\denver_survey.top"
    if (Test-Path $topFile) {
        Write-Host "Opening pre-saved project: $topFile"
        $launched = Start-TopoCalInteractive -FilePath $topFile -WaitSeconds 10
    } else {
        Write-Host "WARNING: denver_survey.top not found, opening empty TopoCal"
        $launched = Start-TopoCalInteractive -WaitSeconds 10
    }

    if (-not $launched) {
        Write-Host "WARNING: TopoCal main window may not be visible"
    }

    Start-Sleep -Seconds 2
    Set-TopoCalForeground | Out-Null

    Stop-EdgeKillerTask -KillerInfo $edgeKiller

    Write-Host "=== Task setup complete — TopoCal open with survey points ==="

} catch {
    Write-Host "ERROR: $_"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
