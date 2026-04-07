#!/bin/bash
echo "=== Exporting configure_database_backup results ==="

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(powershell.exe -Command "[int][double]::Parse((Get-Date -UFormat %s))")

# 1. Check if backup directory exists (Agent should have set path C:\ADAuditBackups)
# Note: The product might create it immediately upon save, or agent might create it manually.
BACKUP_DIR_EXISTS="false"
if [ -d "/cygdrive/c/ADAuditBackups" ]; then
    BACKUP_DIR_EXISTS="true"
fi

# 2. Check for Configuration Changes
# We compare file modification times in the conf directory against task start time
CONF_DIR="/cygdrive/c/Program Files/ManageEngine/ADAudit Plus/conf"
CONFIG_MODIFIED="false"
MODIFIED_FILES=""

if [ -d "$CONF_DIR" ]; then
    # Find files modified after task start
    # Note: Using -newermt if available, or manual comparison
    # Cygwin find usually supports -newermt or we compare timestamp
    
    # Simple check: Count files with mtime > TASK_START
    COUNT=$(find "$CONF_DIR" -type f -newermt "@$TASK_START" 2>/dev/null | wc -l)
    if [ "$COUNT" -gt "0" ]; then
        CONFIG_MODIFIED="true"
        MODIFIED_FILES=$(find "$CONF_DIR" -type f -newermt "@$TASK_START" -printf "%f,")
    fi
    
    # Also check database specific config files if known (database_params.conf etc)
    # Some apps write to ../bin/ or specific xmls
fi

# 3. Capture Final Screenshot
echo "Capturing final screenshot..."
if command -v scrot >/dev/null; then
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
else
    powershell.exe -Command "
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $bitmap = New-Object System.Drawing.Bitmap $screen.Bounds.Width, $screen.Bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($screen.Bounds.X, $screen.Bounds.Y, 0, 0, $bitmap.Size)
    $bitmap.Save('C:\\Users\\Public\\task_final.png')
    " 2>/dev/null || true
    if [ -f "/cygdrive/c/Users/Public/task_final.png" ]; then
        mv "/cygdrive/c/Users/Public/task_final.png" /tmp/task_final.png
    fi
fi

SCREENSHOT_EXISTS="false"
[ -f "/tmp/task_final.png" ] && SCREENSHOT_EXISTS="true"

# 4. Create Result JSON
# Using python one-liner to generate safe JSON
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'task_end': $CURRENT_TIME,
    'backup_dir_exists': True if '$BACKUP_DIR_EXISTS' == 'true' else False,
    'config_modified': True if '$CONFIG_MODIFIED' == 'true' else False,
    'modified_files': '$MODIFIED_FILES',
    'screenshot_exists': True if '$SCREENSHOT_EXISTS' == 'true' else False,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="