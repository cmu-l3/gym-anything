#!/bin/bash
set -e
echo "=== Setting up configure_database_backup task ==="

# 1. Record task start time (using PowerShell to get Unix timestamp to avoid Cygwin/Win time diffs)
powershell.exe -Command "[int][double]::Parse((Get-Date -UFormat %s))" > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Cleanup: Remove backup directory if it exists to ensure agent creates/configures it
if [ -d "/cygdrive/c/ADAuditBackups" ]; then
    echo "Cleaning up existing backup directory..."
    rm -rf "/cygdrive/c/ADAuditBackups"
fi

# 3. Snapshot configuration state (to detect changes later)
# We look at the conf directory where settings are typically stored or referenced
CONF_DIR="/cygdrive/c/Program Files/ManageEngine/ADAudit Plus/conf"
if [ -d "$CONF_DIR" ]; then
    echo "Snapshotting configuration directory..."
    # Create a simple list of file timestamps
    find "$CONF_DIR" -type f -exec stat -c "%n %Y" {} \; > /tmp/initial_conf_state.txt
else
    echo "WARNING: Conf directory not found at expected path"
    touch /tmp/initial_conf_state.txt
fi

# 4. Ensure ADAudit Plus service is running
echo "Checking ADAudit Plus service..."
powershell.exe -Command "
    $service = Get-Service -Name 'ManageEngine ADAudit Plus' -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne 'Running') {
        Start-Service -Name 'ManageEngine ADAudit Plus'
        Start-Sleep -Seconds 10
    }
"

# 5. Launch Browser (Edge) to Login Page
echo "Launching Microsoft Edge..."
# Kill existing edge instances
taskkill.exe /F /IM msedge.exe 2>/dev/null || true
sleep 2

# Start Edge maximized
powershell.exe -Command "Start-Process msedge.exe -ArgumentList '--start-maximized', '--new-window', 'http://localhost:8081/login.do' -WindowStyle Maximized"

# 6. Wait for window to settle
sleep 5

# 7. Take initial screenshot
echo "Capturing initial state..."
# Using nircmd if available, or powershell fallback, or scour/screenshot cmd provided by env
# Assuming standard gym environment has a screenshot tool or 'scrot' via cygwin X
# If strictly Windows without X, we rely on the framework's periodic capture, 
# but for the script we'll try a powershell capture if scrot fails.
if command -v scrot >/dev/null; then
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
else
    powershell.exe -Command "
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $bitmap = New-Object System.Drawing.Bitmap $screen.Bounds.Width, $screen.Bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($screen.Bounds.X, $screen.Bounds.Y, 0, 0, $bitmap.Size)
    $bitmap.Save('C:\\Users\\Public\\task_initial.png')
    " 2>/dev/null || true
    # Move from Win path to unix path if needed, or leave for export
    if [ -f "/cygdrive/c/Users/Public/task_initial.png" ]; then
        mv "/cygdrive/c/Users/Public/task_initial.png" /tmp/task_initial.png
    fi
fi

echo "=== Task setup complete ==="