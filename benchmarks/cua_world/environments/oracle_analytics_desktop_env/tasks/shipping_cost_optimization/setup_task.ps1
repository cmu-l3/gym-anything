# Setup script for shipping_cost_optimization task.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_shipping_cost_optimization.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up shipping_cost_optimization task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    Kill-OADProcesses

    $dataDir = "C:\Users\Docker\Desktop\OracleAnalyticsData"
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
    $srcFile = "C:\workspace\data\order_lines.csv"
    $dstFile = "$dataDir\order_lines.csv"
    if (-not (Test-Path $dstFile)) {
        Copy-Item $srcFile -Destination $dstFile -Force
    }
    Write-Host "Data file ready at: $dstFile"

    # Remove previous output workbooks (BEFORE recording timestamp)
    $cleanPaths = @(
        "C:\Users\Docker\Documents\shipping_optimization.dva",
        "C:\Users\Docker\Desktop\shipping_optimization.dva",
        "C:\Users\Docker\shipping_optimization.dva"
    )
    foreach ($p in $cleanPaths) {
        Remove-Item $p -Force -Recurse -ErrorAction SilentlyContinue
    }

    # Record task start timestamp
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_shipping_opt.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $ts"

    $oadExe = Find-OADExe
    Write-Host "OAD executable: $oadExe"
    Launch-OADInteractive -OADExe $oadExe -WaitSeconds 25

    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        $taskName = "DismissDialogs_ShipOpt_GA"
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

    $oadProc = Get-OADProcess | Select-Object -First 1
    if ($oadProc) {
        Write-Host "OAD is running (PID: $($oadProc.Id))"
    } else {
        Write-Host "WARNING: OAD process not found after launch."
    }

    Write-Host "=== shipping_cost_optimization setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
