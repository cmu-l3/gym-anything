#!/bin/bash
set -e

# Define paths
TASK_DIR="/workspace/tasks/configure_fixed_price_axis"
START_TIME_FILE="/tmp/task_start_time.txt"
INITIAL_SCREENSHOT="/tmp/task_initial.png"

echo "=== Setting up Configure Fixed Price Axis task ==="

# 1. Record Start Time (Unix Timestamp)
date +%s > "$START_TIME_FILE"
echo "Task start time recorded: $(cat $START_TIME_FILE)"

# 2. Create a PowerShell setup script to handle Windows/NinjaTrader specific setup
#    This script ensures NT8 is running and minimized/maximized correctly
PS_SETUP_SCRIPT="/tmp/setup_task_internal.ps1"

cat << 'EOF' > "$PS_SETUP_SCRIPT"
$ErrorActionPreference = "Stop"

# Define Paths
$NT8Path = "C:\Program Files\NinjaTrader 8\bin\NinjaTrader.exe"
$ProcessName = "NinjaTrader"

# Check if NinjaTrader is running
$process = Get-Process $ProcessName -ErrorAction SilentlyContinue

if (-not $process) {
    Write-Host "Starting NinjaTrader 8..."
    Start-Process -FilePath $NT8Path
    
    # Wait for process to stabilize
    Start-Sleep -Seconds 15
} else {
    Write-Host "NinjaTrader 8 is already running."
}

# Ensure window is restored and focused (using WScript.Shell for basic activation)
$wshell = New-Object -ComObject wscript.shell
if ($wshell.AppActivate("NinjaTrader")) {
    Start-Sleep -Milliseconds 500
    # Send Maximize shortcut (Alt+Space, x) - simplistic approach, 
    # specific window management might require C# pinvoke, keeping it simple for now
    # $wshell.SendKeys("% x") 
}

Write-Host "NinjaTrader setup checks complete."
EOF

# 3. Execute the PowerShell script
#    Assuming 'powershell' is in the PATH (standard for Windows containers/VMs)
echo "Executing PowerShell setup logic..."
powershell.exe -ExecutionPolicy Bypass -File "$PS_SETUP_SCRIPT"

# 4. Take Initial Screenshot
#    Using 'scrot' if available (Linux host) or a PowerShell method if strictly Windows
if command -v scrot &> /dev/null; then
    DISPLAY=:1 scrot "$INITIAL_SCREENSHOT"
else
    # Fallback to PowerShell screenshot
    powershell.exe -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('{PRTSC}'); Start-Sleep -m 200; \$img = [System.Windows.Forms.Clipboard]::GetImage(); if (\$img) { \$img.Save('$INITIAL_SCREENSHOT') }"
fi

echo "=== Setup Complete ==="