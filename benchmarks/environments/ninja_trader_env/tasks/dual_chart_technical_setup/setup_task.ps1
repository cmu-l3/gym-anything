Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_dual_chart_technical_setup.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up dual_chart_technical_setup task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) {
        throw "Missing task utils: $utils"
    }
    . $utils

    # Kill any existing NinjaTrader
    Get-Process NinjaTrader -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    # Ensure task output directory exists
    $outputDir = "C:\Users\Docker\Desktop\NinjaTraderTasks"
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

    # Record baseline: workspace file state BEFORE task starts
    $ntDocDir = "C:\Users\Docker\Documents\NinjaTrader 8"
    $wsDir = Join-Path $ntDocDir "workspaces"

    $baselineInfo = @{
        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        workspace_files = @()
    }
    if (Test-Path $wsDir) {
        Get-ChildItem $wsDir -Filter "*.xml" -ErrorAction SilentlyContinue | ForEach-Object {
            $baselineInfo.workspace_files += @{
                name = $_.Name
                size = $_.Length
                modified = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
    }
    $baselineInfo | ConvertTo-Json -Depth 5 | Out-File "$outputDir\dual_chart_baseline.json" -Encoding utf8

    # Record task start timestamp
    [int](Get-Date -UFormat %s) | Out-File "$outputDir\task_start_timestamp.txt" -Encoding utf8

    # Launch NinjaTrader
    $ntExe = Find-NTExe
    Write-Host "NinjaTrader executable: $ntExe"
    Launch-NTInteractive -NTExe $ntExe -WaitSeconds 20

    # Dismiss startup dialogs
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Write-Host "Dismissing dialogs..."
        & $dismissScript
    }

    # Verify NinjaTrader is running
    $ntProc = Get-Process NinjaTrader -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ntProc) {
        Write-Host "NinjaTrader is running (PID: $($ntProc.Id))"
    } else {
        Write-Host "WARNING: NinjaTrader process not found."
    }

    Write-Host "=== dual_chart_technical_setup task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
