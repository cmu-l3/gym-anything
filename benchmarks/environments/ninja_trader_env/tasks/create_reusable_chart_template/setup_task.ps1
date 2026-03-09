Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_create_reusable_chart_template.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up create_reusable_chart_template task ==="

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

    # Record baseline: check if template already exists and remove it
    $ntDocDir = "C:\Users\Docker\Documents\NinjaTrader 8"
    $templateDir = Join-Path $ntDocDir "templates\Chart"

    # Remove any pre-existing SwingTrading template
    if (Test-Path $templateDir) {
        Get-ChildItem $templateDir -Filter "SwingTrading*" -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item $_.FullName -Force
            Write-Host "Removed pre-existing template: $($_.Name)"
        }
    }

    # Record baseline template state
    $baselineInfo = @{
        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        template_dir_exists = (Test-Path $templateDir)
        existing_templates = @()
    }
    if (Test-Path $templateDir) {
        Get-ChildItem $templateDir -ErrorAction SilentlyContinue | ForEach-Object {
            $baselineInfo.existing_templates += $_.Name
        }
    }
    $baselineInfo | ConvertTo-Json -Depth 5 | Out-File "$outputDir\chart_template_baseline.json" -Encoding utf8

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

    Write-Host "=== create_reusable_chart_template task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
