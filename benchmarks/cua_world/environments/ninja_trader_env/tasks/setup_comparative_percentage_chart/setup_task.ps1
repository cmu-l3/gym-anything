# Note: This is a Windows environment, so we write a PowerShell script
# saved as setup_task.ps1 in the container.

Write-Host "=== Setting up Comparative Percentage Chart Task ==="

# 1. timestamp for anti-gaming
$startTime = [int][double]::Parse((Get-Date -UFormat %s))
$startTime | Out-File -FilePath "C:\tmp\task_start_time.txt" -Encoding ascii

# 2. Ensure NinjaTrader is running
$process = Get-Process "NinjaTrader" -ErrorAction SilentlyContinue
if (-not $process) {
    Write-Host "Starting NinjaTrader..."
    # Assuming standard install path or shortcut
    Start-Process "C:\Program Files\NinjaTrader 8\bin\NinjaTrader.exe"
    
    # Wait for UI
    Start-Sleep -Seconds 15
}

# 3. Ensure window is maximized (using simple helper or assumed state)
# We can try to use a utility if available, otherwise rely on user
# In this env, we assume standard window state is manageable.

# 4. Clean up any previous result files
if (Test-Path "C:\tmp\task_result.json") {
    Remove-Item "C:\tmp\task_result.json"
}
if (Test-Path "C:\tmp\task_final.png") {
    Remove-Item "C:\tmp\task_final.png"
}

# 5. Capture initial screenshot (if tools available)
# Using python/screenshot util if present in env, otherwise skip
Write-Host "=== Setup Complete ==="