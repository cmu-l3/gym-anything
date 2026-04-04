#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Crash Recovery Result ==="

WORKSPACE_DIR="/home/ga/workspace/crash_recovery_test"

# Give VSCode time to restore and agent time to save
sleep 2

# Try to save all files if VSCode is open
if pgrep -f "code" > /dev/null; then
    echo "VSCode is running, attempting to save all files..."
    focus_vscode_window
    {
        safe_xdotool ga :1 key --delay 200 ctrl+k s
        sleep 2
        safe_xdotool ga :1 key --delay 200 ctrl+shift+s
        sleep 2
    } || {
        echo "⚠️ Could not send save command"
    }
fi

# Wait for files to be saved
sleep 2

# Export the actual file contents for verification
mkdir -p /tmp/crash_recovery_result
chmod 777 /tmp/crash_recovery_result

if [ -f "$WORKSPACE_DIR/routes.py" ]; then
    cp "$WORKSPACE_DIR/routes.py" /tmp/crash_recovery_result/routes_actual.py
    echo "✅ Exported routes.py"
else
    echo "⚠️ routes.py not found"
    touch /tmp/crash_recovery_result/routes_actual.py
fi

if [ -f "$WORKSPACE_DIR/validation.py" ]; then
    cp "$WORKSPACE_DIR/validation.py" /tmp/crash_recovery_result/validation_actual.py
    echo "✅ Exported validation.py"
else
    echo "⚠️ validation.py not found"
    touch /tmp/crash_recovery_result/validation_actual.py
fi

if [ -f "$WORKSPACE_DIR/test_validation.py" ]; then
    cp "$WORKSPACE_DIR/test_validation.py" /tmp/crash_recovery_result/test_actual.py
    echo "✅ Exported test_validation.py"
else
    echo "⚠️ test_validation.py not found"
    touch /tmp/crash_recovery_result/test_actual.py
fi

# Also export backup directory info for diagnostic purposes
BACKUP_BASE="/home/ga/.config/Code/Backups"
if [ -d "$BACKUP_BASE" ]; then
    ls -laR "$BACKUP_BASE" > /tmp/crash_recovery_result/backup_structure.txt 2>&1
    echo "✅ Backup structure exported"
else
    echo "No backup directory" > /tmp/crash_recovery_result/backup_structure.txt
fi

echo "✅ Export complete"
echo "Results saved to: /tmp/crash_recovery_result/"