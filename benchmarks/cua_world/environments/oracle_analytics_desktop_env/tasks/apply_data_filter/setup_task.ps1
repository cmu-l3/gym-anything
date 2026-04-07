# Setup script for apply_data_filter task.
# Ensures clean state and opens Oracle Analytics Desktop in the interactive desktop session.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_apply_data_filter.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up apply_data_filter task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) {
        throw "Missing task utils: $utils"
    }
    . $utils

    # Close any open Oracle Analytics Desktop instances
    Kill-OADProcesses

    # Ensure data files exist on the Desktop
    $dataDir = "C:\Users\Docker\Desktop\OracleAnalyticsData"
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
    $dataFile = "$dataDir\order_lines.csv"
    if (-not (Test-Path $dataFile)) {
        Copy-Item "C:\workspace\data\order_lines.csv" -Destination $dataFile -Force
    }
    Write-Host "Data file ready at: $dataFile"

    # Remove any previous saved workbooks
    Remove-Item "C:\Users\Docker\Desktop\filtered_profit_report*" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Docker\Documents\filtered_profit_report*" -Force -ErrorAction SilentlyContinue

    # Find and launch Oracle Analytics Desktop
    $oadExe = Find-OADExe
    Write-Host "OAD executable: $oadExe"
    Write-Host "Launching Oracle Analytics Desktop via scheduled task..."
    Launch-OADInteractive -OADExe $oadExe -WaitSeconds 25

    # Dismiss dialogs
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Write-Host "Dismissing dialogs..."
        $taskName = "DismissDialogs_GA"
        $prevEAP = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            schtasks /Create /TN $taskName /TR "powershell -ExecutionPolicy Bypass -File $dismissScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
            schtasks /Run /TN $taskName 2>$null
            Start-Sleep -Seconds 20
        } finally {
            schtasks /Delete /TN $taskName /F 2>$null
            $ErrorActionPreference = $prevEAP
        }
    }

    # Verify OAD is running
    $oadProc = Get-OADProcess | Select-Object -First 1
    if ($oadProc) {
        Write-Host "Oracle Analytics Desktop is running (PID: $($oadProc.Id))"
    } else {
        Write-Host "WARNING: Oracle Analytics Desktop process not found after launch."
    }

    Write-Host "=== apply_data_filter task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
