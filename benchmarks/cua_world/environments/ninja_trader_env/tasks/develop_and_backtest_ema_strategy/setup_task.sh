#!/bin/bash
echo "=== Setting up develop_and_backtest_ema_strategy task ==="

# Define paths (using Windows format for PowerShell)
STRATEGY_PATH="C:\Users\Docker\Documents\NinjaTrader 8\bin\Custom\Strategies\SampleEMACrossover.cs"
COMPILED_PATH="C:\Users\Docker\Documents\NinjaTrader 8\bin\Custom\Strategies\SampleEMACrossover.cs.compiled"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create a PowerShell setup script
cat > /tmp/setup_nt8.ps1 << 'PSEOF'
Write-Host "Cleaning up previous strategy files..."
$StrategyPath = "C:\Users\Docker\Documents\NinjaTrader 8\bin\Custom\Strategies\SampleEMACrossover.cs"
if (Test-Path $StrategyPath) {
    Remove-Item $StrategyPath -Force
    Write-Host "Removed $StrategyPath"
}

# Ensure NinjaTrader is running
if (-not (Get-Process "NinjaTrader" -ErrorAction SilentlyContinue)) {
    Write-Host "Starting NinjaTrader..."
    Start-Process "C:\Program Files (x86)\NinjaTrader 8\bin\NinjaTrader.exe"
    
    # Wait for the process to stabilize
    Start-Sleep -Seconds 15
} else {
    Write-Host "NinjaTrader is already running."
}

# Clean workspace to ensure fresh start (optional, but good for verification)
# We won't delete all workspaces, just ensure we are in a clean state if possible.
# For this task, existing workspaces don't strictly block the agent, so we leave them.
PSEOF

# Execute the PowerShell script
powershell.exe -ExecutionPolicy Bypass -File "C:\workspace\tasks\develop_and_backtest_ema_strategy\setup_task.ps1" 2>/dev/null || \
powershell.exe -ExecutionPolicy Bypass -File "/tmp/setup_nt8.ps1"

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="