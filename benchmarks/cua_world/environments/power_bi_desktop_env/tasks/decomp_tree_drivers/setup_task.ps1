# Setup script for decomp_tree_drivers task.
# Ensures clean state and opens Power BI Desktop in the interactive desktop session.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_decomp_tree_drivers.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up decomp_tree_drivers task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) {
        throw "Missing task utils: $utils"
    }
    . $utils

    # Close any open Power BI windows and sub-processes
    Get-Process PBIDesktop -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process msmdsrv -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Ensure the data file exists on the Desktop
    $dataFile = "C:\Users\Docker\Desktop\PowerBITasks\sales_data.csv"
    if (-not (Test-Path $dataFile)) {
        $destDir = "C:\Users\Docker\Desktop\PowerBITasks"
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        Copy-Item "C:\workspace\data\sales_data.csv" -Destination $dataFile -Force
    }
    Write-Host "Data file ready at: $dataFile"

    # Record task start timestamp
    [int][double]::Parse((Get-Date -UFormat %s)) | Set-Content "C:\Users\Docker\task_start_timestamp_decomp_tree.txt"

    # Find and launch Power BI Desktop
    $pbiExe = Find-PowerBIExe
    Write-Host "Power BI executable: $pbiExe"
    Write-Host "Launching Power BI Desktop via scheduled task (interactive desktop)..."
    Launch-PowerBIInteractive -PowerBIExe $pbiExe -WaitSeconds 15

    # Best-effort: dismiss common first-run dialogs in the interactive session.
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Write-Host "Dismissing dialogs via scheduled task..."
        $taskName = "DismissDialogs_GA"
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

    Write-Host "=== decomp_tree_drivers task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
