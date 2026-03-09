# setup_task.ps1 (Powershell script for Windows Environment)
$ErrorActionPreference = "Stop"
Write-Host "=== Setting up annotate_chart_with_drawings task ==="

# 1. Record task start time for anti-gaming verification
# Using Unix timestamp
$startTime = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$startTime | Out-File "C:\workspace\tasks\annotate_chart_with_drawings\start_time.txt" -Encoding ascii
Write-Host "Task start time recorded: $startTime"

# 2. Cleanup previous result files
$resultPath = "C:\Users\Docker\Desktop\NinjaTraderTasks\annotate_chart_with_drawings_result.json"
if (Test-Path $resultPath) {
    Remove-Item $resultPath -Force
}

# 3. Ensure NinjaTrader 8 is running
$proc = Get-Process NinjaTrader -ErrorAction SilentlyContinue
if (-not $proc) {
    Write-Host "Starting NinjaTrader..."
    # Assuming standard install path defined in env
    Start-Process "C:\Program Files (x86)\NinjaTrader 8\bin\NinjaTrader.exe"
    
    # Wait for process to stabilize
    Start-Sleep -Seconds 15
}

# 4. Bring window to front (Basic attempt, though agent usually handles focus)
# Using a simple shell object method if available, otherwise relying on agent
try {
    $wshell = New-Object -ComObject wscript.shell
    $wshell.AppActivate("NinjaTrader")
} catch {
    Write-Host "Focus attempt skipped"
}

Write-Host "=== Setup complete ==="