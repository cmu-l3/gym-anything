###############################################################################
# setup_task.ps1 — pre_task hook for import_survey_points
# Launches TopoCal with an empty drawing ready for the agent to import data
###############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_import_survey_points.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Setting up import_survey_points task ==="

    # Source shared utilities
    . "C:\workspace\scripts\task_utils.ps1"

    # Kill Edge to prevent session restore interference
    $edgeKiller = Start-EdgeKillerTask
    Close-Browsers

    # Ensure infrastructure is running
    Ensure-HTTPServer
    Ensure-PyAutoGUIServer

    # Ensure survey data is on Desktop
    $dataDir = "C:\Users\Docker\Desktop\SurveyData"
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    if (-not (Test-Path "$dataDir\survey_points.csv")) {
        Copy-Item "C:\workspace\data\survey_points.csv" "$dataDir\survey_points.csv" -Force
        Write-Host "Copied survey_points.csv to Desktop"
    }

    # Launch TopoCal (empty drawing — no file argument)
    # Handle-TopoCalActivation is called automatically inside Start-TopoCalInteractive
    $launched = Start-TopoCalInteractive -WaitSeconds 10
    if (-not $launched) {
        Write-Host "WARNING: TopoCal main window may not be visible yet"
    }

    # Bring TopoCal to foreground
    Start-Sleep -Seconds 2
    Set-TopoCalForeground | Out-Null

    # Stop Edge killer
    Stop-EdgeKillerTask -KillerInfo $edgeKiller

    Write-Host "=== Task setup complete — TopoCal open with empty drawing ==="

} catch {
    Write-Host "ERROR: $_"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
