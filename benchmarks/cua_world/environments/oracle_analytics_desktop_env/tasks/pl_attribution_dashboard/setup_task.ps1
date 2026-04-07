# Setup script for pl_attribution_dashboard task.
# Ensures clean state and opens Oracle Analytics Desktop.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_pl_attribution_dashboard.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up pl_attribution_dashboard task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) {
        throw "Missing task utils: $utils"
    }
    . $utils

    # Kill any running OAD instances
    Kill-OADProcesses

    # Ensure data files exist on the Desktop
    $dataDir = "C:\Users\Docker\Desktop\OracleAnalyticsData"
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
    $srcFile = "C:\workspace\data\order_lines.csv"
    $dstFile = "$dataDir\order_lines.csv"
    if (-not (Test-Path $dstFile)) {
        Copy-Item $srcFile -Destination $dstFile -Force
    }
    Write-Host "Data file ready at: $dstFile"

    # Remove any previous output workbook files (BEFORE recording timestamp)
    $cleanPaths = @(
        "C:\Users\Docker\Desktop\pl_attribution.dva",
        "C:\Users\Docker\Documents\pl_attribution.dva",
        "C:\Users\Docker\Desktop\pl_attribution",
        "C:\Users\Docker\Documents\pl_attribution"
    )
    foreach ($p in $cleanPaths) {
        Remove-Item $p -Force -Recurse -ErrorAction SilentlyContinue
    }

    # Record task start timestamp AFTER cleanup
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_pl_attribution.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $ts"

    # Find and launch Oracle Analytics Desktop
    $oadExe = Find-OADExe
    Write-Host "OAD executable: $oadExe"
    Write-Host "Launching Oracle Analytics Desktop via scheduled task..."
    Launch-OADInteractive -OADExe $oadExe -WaitSeconds 25

    # Dismiss dialogs
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Write-Host "Dismissing dialogs..."
        $taskName = "DismissDialogs_PL_GA"
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

    Write-Host "=== pl_attribution_dashboard task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
