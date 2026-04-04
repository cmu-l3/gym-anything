#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Purge Commented Dead Code Result ==="

WORKSPACE_DIR="/home/ga/workspace/comment_cleanup_project"

# Focus VSCode and trigger save all
focus_vscode_window
sleep 1

# Save all files (Ctrl+K S is the "Save All" shortcut)
echo "Triggering Save All..."
{
    safe_xdotool ga :1 key --delay 100 ctrl+k
    sleep 0.3
    safe_xdotool ga :1 key --delay 100 s
} || {
    echo "⚠️ Save All shortcut may have failed, trying individual save"
    safe_xdotool ga :1 key --delay 200 ctrl+s
}

sleep 2

# Wait for files to be written
for file in "src/main.py" "src/utils.py" "src/data_processor.py" "src/legacy_handler.py" "tests/test_main.py"; do
    wait_for_file "$WORKSPACE_DIR/$file" 3 || echo "⚠️ Warning: $file may not exist"
done

echo "✅ Export complete"
echo "Files should be saved at: $WORKSPACE_DIR"