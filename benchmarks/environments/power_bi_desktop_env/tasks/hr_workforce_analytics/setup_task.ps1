# Setup script for hr_workforce_analytics task.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_hr_workforce_analytics.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up hr_workforce_analytics task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    Get-Process PBIDesktop -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process msmdsrv -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Remove pre-existing output files
    $targetPbix = "C:\Users\Docker\Desktop\HR_Workforce_Analytics.pbix"
    foreach ($f in @($targetPbix, "C:\Users\Docker\Desktop\hr_workforce_result.json")) {
        if (Test-Path $f) { Remove-Item $f -Force; Write-Host "Removed: $f" }
    }

    # Ensure source data file is present
    $dataFile = "C:\Users\Docker\Desktop\PowerBITasks\employee_performance.csv"
    if (-not (Test-Path $dataFile)) {
        $destDir = "C:\Users\Docker\Desktop\PowerBITasks"
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        Copy-Item "C:\workspace\data\employee_performance.csv" -Destination $dataFile -Force
    }
    Write-Host "Data file ready: $dataFile"

    # Record start timestamp
    $epoch = [int][double]::Parse((Get-Date -UFormat %s))
    Set-Content -Path "C:\Users\Docker\task_start_timestamp_hr.txt" -Value "$epoch"
    Write-Host "Start timestamp: $epoch"

    # Record baseline
    Set-Content -Path "C:\Users\Docker\task_baseline_hr.txt" -Value "pbix_exists_at_start=false"

    # Launch Power BI Desktop
    $pbiExe = Find-PowerBIExe
    Write-Host "Launching Power BI Desktop..."
    Launch-PowerBIInteractive -PowerBIExe $pbiExe -WaitSeconds 15

    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        $taskName = "DismissDialogs_HR"
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
    }

    $pbiProc = Get-Process PBIDesktop -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pbiProc) { Write-Host "Power BI Desktop running (PID: $($pbiProc.Id))" }
    else { Write-Host "WARNING: Power BI Desktop not found after launch." }

    Write-Host "=== hr_workforce_analytics setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
