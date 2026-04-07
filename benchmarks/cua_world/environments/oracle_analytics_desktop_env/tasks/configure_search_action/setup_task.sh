#!/bin/bash
echo "=== Setting up Configure Search Action Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Oracle Analytics Desktop is running
# Using powershell to check/start process since this is a Windows environment
echo "Checking Oracle Analytics Desktop status..."
powershell.exe -Command "
    \$proc = Get-Process -Name 'DVD' -ErrorAction SilentlyContinue
    if (!\$proc) {
        Write-Host 'Starting Oracle Analytics Desktop...'
        Start-Process 'C:\Program Files\Oracle Analytics Desktop\DVD.exe'
        Start-Sleep -Seconds 15
    } else {
        Write-Host 'Oracle Analytics Desktop is already running.'
    }
"

# Maximize the window (Best effort via Powershell)
powershell.exe -Command "
    \$wshell = New-Object -ComObject WScript.Shell
    \$wshell.AppActivate('Oracle Analytics Desktop')
    Start-Sleep -Milliseconds 500
    # Send Alt+Space, then x to maximize
    \$wshell.SendKeys('% ')
    Start-Sleep -Milliseconds 200
    \$wshell.SendKeys('x')
"

# Take initial screenshot using available tools (scrot on host or similar)
# Assuming standard gym-anything hook environment
if command -v scrot >/dev/null 2>&1; then
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
fi

echo "=== Setup Complete ==="