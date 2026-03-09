#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Fix Timezone Handling Result ==="

WORKSPACE_DIR="/home/ga/workspace/scheduler_app"

# Focus VSCode and save all files
focus_vscode_window
{
    # Try to save all files
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to save files via hotkey; continuing"
}

# Wait for files to be written
sleep 2

# Verify files exist
for file in scheduler.py models.py; do
    if [ -f "$WORKSPACE_DIR/$file" ]; then
        echo "✅ $file exists"
    else
        echo "⚠️ $file not found"
    fi
done

echo "✅ Export complete"
echo "Modified files should be at: $WORKSPACE_DIR"