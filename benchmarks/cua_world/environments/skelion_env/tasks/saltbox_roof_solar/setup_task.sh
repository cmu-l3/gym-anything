#!/bin/bash
echo "=== Setting up saltbox_roof_solar task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Start SketchUp using PowerShell if not already running
# We use PowerShell inside the Windows environment to handle processes
powershell.exe -Command "
\$ErrorActionPreference = 'SilentlyContinue'
if (-not (Get-Process -Name 'SketchUp')) {
    Start-Process 'C:\Program Files\SketchUp\SketchUp 2017\SketchUp.exe'
    Start-Sleep -Seconds 15
}
"

# Clean any previous output file to ensure a clean slate
rm -f "/c/Users/Docker/Documents/saltbox_solar.skp" 2>/dev/null || true
powershell.exe -Command "
\$ErrorActionPreference = 'SilentlyContinue'
Remove-Item -Force -Path 'C:\Users\Docker\Documents\saltbox_solar.skp'
"

# Dismiss Welcome dialogs and stabilize UI
powershell.exe -Command "
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait('{ESCAPE}')
Start-Sleep -Seconds 1
[System.Windows.Forms.SendKeys]::SendWait('{ESCAPE}')
"

echo "=== Task setup complete ==="