# Note: This environment uses PowerShell for scripts, but the framework expects a .sh hook definition usually.
# However, the environment definition uses PowerShell in hooks.
# To be consistent with the requested format, I will provide the PowerShell content 
# that should be saved as setup_task.ps1, as indicated in the task.json hooks.

# <file name="setup_task.ps1">
Write-Host "=== Setting up Configure Drawing Tool Alert task ==="

# 1. Record start time
$startTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$startTime | Out-File -FilePath "C:\tmp\task_start_time.txt" -Force

# 2. Clean up previous results
Remove-Item "C:\Users\Docker\Desktop\NinjaTraderTasks\configure_drawing_tool_alert_result.json" -ErrorAction SilentlyContinue

# 3. Ensure NinjaTrader is running
$ntProcess = Get-Process -Name "NinjaTrader" -ErrorAction SilentlyContinue
if (-not $ntProcess) {
    Write-Host "Starting NinjaTrader..."
    Start-Process "C:\Program Files\NinjaTrader 8\bin\NinjaTrader.exe"
    Start-Sleep -Seconds 15
}

# 4. Wait for window and maximize (using specialized script or assuming env handles it)
# The environment usually handles basic window management, but we ensure focus here if possible.
# (PowerShell window manipulation is limited without external DLLs, relying on agent/env for visibility)

# 5. Take initial screenshot (simulated by creating a marker or handled by framework)
# The framework handles the screenshot via the gym observation.

Write-Host "=== Task setup complete ==="
# </file>