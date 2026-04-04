# Setup script for sales_kpi_dashboard task.
# Records baseline state, ensures clean environment, launches Power BI Desktop.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_sales_kpi_dashboard.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up sales_kpi_dashboard task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) {
        throw "Missing task utils: $utils"
    }
    . $utils

    # Kill any running Power BI instances
    Get-Process PBIDesktop -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process msmdsrv -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Remove any pre-existing target .pbix to ensure clean baseline
    $targetPbix = "C:\Users\Docker\Desktop\Sales_KPI_Dashboard.pbix"
    if (Test-Path $targetPbix) {
        Remove-Item $targetPbix -Force
        Write-Host "Removed pre-existing target file: $targetPbix"
    }

    # Remove any pre-existing result JSON
    $resultJson = "C:\Users\Docker\Desktop\sales_kpi_result.json"
    if (Test-Path $resultJson) {
        Remove-Item $resultJson -Force
    }

    # Ensure the source data file exists
    $dataFile = "C:\Users\Docker\Desktop\PowerBITasks\sales_data.csv"
    if (-not (Test-Path $dataFile)) {
        $destDir = "C:\Users\Docker\Desktop\PowerBITasks"
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        Copy-Item "C:\workspace\data\sales_data.csv" -Destination $dataFile -Force
    }
    Write-Host "Data file ready at: $dataFile"

    # Record start timestamp (epoch seconds) for anti-gaming
    $epoch = [int][double]::Parse((Get-Date -UFormat %s))
    Set-Content -Path "C:\Users\Docker\task_start_timestamp_sales_kpi.txt" -Value "$epoch"
    Write-Host "Start timestamp recorded: $epoch"

    # Record baseline - confirm target file does NOT exist
    $baselineExists = (Test-Path $targetPbix).ToString().ToLower()
    Set-Content -Path "C:\Users\Docker\task_baseline_sales_kpi.txt" -Value "target_exists_at_start=$baselineExists"
    Write-Host "Baseline recorded: target_exists_at_start=$baselineExists"

    # Find and launch Power BI Desktop interactively
    $pbiExe = Find-PowerBIExe
    Write-Host "Power BI executable: $pbiExe"
    Write-Host "Launching Power BI Desktop..."
    Launch-PowerBIInteractive -PowerBIExe $pbiExe -WaitSeconds 15

    # Dismiss common startup dialogs
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Write-Host "Dismissing startup dialogs..."
        $taskName = "DismissDialogs_SKD"
        $prevEAP = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            schtasks /Create /TN $taskName /TR "powershell -ExecutionPolicy Bypass -File $dismissScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
            schtasks /Run /TN $taskName 2>$null
            Start-Sleep -Seconds 28
        } finally {
            schtasks /Delete /TN $taskName /F 2>$null
            $ErrorActionPreference = $prevEAP
        }
        Write-Host "Dialog dismissal complete."
    }

    # Verify Power BI is running
    $pbiProc = Get-Process PBIDesktop -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pbiProc) {
        Write-Host "Power BI Desktop is running (PID: $($pbiProc.Id))"
    } else {
        Write-Host "WARNING: Power BI Desktop process not found after launch."
    }

    Write-Host "=== sales_kpi_dashboard setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
