#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Implement Stub From Usage Result ==="

# Focus VSCode and save
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to save with keyboard shortcut; continuing"
}

# Wait for file to be written
wait_for_file "/home/ga/workspace/config_manager/utils.py" 5

# Give filesystem time to sync
sleep 1

echo "✅ Export complete"
echo "Implementation file: /home/ga/workspace/config_manager/utils.py"