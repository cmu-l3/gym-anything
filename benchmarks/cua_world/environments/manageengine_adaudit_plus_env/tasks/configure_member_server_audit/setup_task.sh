#!/bin/bash
set -e
echo "=== Setting up configure_member_server_audit task ==="

# Define paths
TASK_DIR="/workspace/tasks/configure_member_server_audit"
mkdir -p "$TASK_DIR"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous configuration for APP-SERVER-01
# We use PowerShell to interact with the ADAudit Plus database or config files if possible,
# or just ensure we start fresh. For this task, we'll try to remove it from the DB if it exists,
# but since direct DB access might be complex, we'll rely on the agent handling "Server already exists" 
# or we assume a clean slate from the environment reset.
# Here we'll just log the initial state.

echo "Checking initial state..."
powershell.exe -Command "
    \$ErrorActionPreference = 'SilentlyContinue'
    # Check if ADAudit Plus service is running
    \$service = Get-Service -Name 'ManageEngine ADAudit Plus'
    if (\$service.Status -ne 'Running') {
        Write-Host 'Starting ADAudit Plus Service...'
        Start-Service 'ManageEngine ADAudit Plus'
        Start-Sleep -Seconds 20
    }
"

# 2. Prepare the browser
echo "Preparing browser..."
# Kill existing browsers
taskkill.exe /F /IM msedge.exe /T 2>/dev/null || true
taskkill.exe /F /IM chrome.exe /T 2>/dev/null || true

# Wait for service port 8081
echo "Waiting for ADAudit Plus web interface..."
for i in {1..30}; do
    if powershell.exe -Command "Test-NetConnection -ComputerName localhost -Port 8081 -InformationLevel Quiet" | grep -q "True"; then
        echo "Web interface is ready."
        break
    fi
    sleep 2
done

# Launch Edge to the login page
# Using nohup to keep it running after script exits
'/C/Program Files (x86)/Microsoft/Edge/Application/msedge.exe' --start-maximized "http://localhost:8081" &
sleep 5

# 3. Capture Initial State Screenshot
echo "Capturing initial screenshot..."
# Using a PowerShell script to capture screenshot if scrot isn't available in Windows/GitBash
# Or assume the standard Linux tools if this is a VNC-to-Linux bridge.
# Based on env.json "base": "windows-11", we likely need a Windows screenshot tool or PowerShell.
powershell.exe -Command "
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    \$screen = [System.Windows.Forms.Screen]::PrimaryScreen
    \$bitmap = New-Object System.Drawing.Bitmap \$screen.Bounds.Width, \$screen.Bounds.Height
    \$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
    \$graphics.CopyFromScreen(\$screen.Bounds.X, \$screen.Bounds.Y, 0, 0, \$bitmap.Size)
    \$bitmap.Save('C:\\Users\\Public\\task_initial.png')
" 2>/dev/null || true

# Move screenshot to /tmp if needed for the framework
if [ -f "/c/Users/Public/task_initial.png" ]; then
    cp "/c/Users/Public/task_initial.png" /tmp/task_initial.png
fi

echo "=== Task setup complete ==="