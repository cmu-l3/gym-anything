#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Cleanup Python Imports Result ==="

# Focus VSCode and save
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to save file; continuing"
}

sleep 2

# Wait for file to be written
wait_for_file "/home/ga/workspace/cleanup_imports_task/myproject/data_processor.py" 5

# Copy the modified file to /tmp for verification
RESULT_DIR="/tmp/cleanup_imports_result"
mkdir -p "$RESULT_DIR"

if [ -f "/home/ga/workspace/cleanup_imports_task/myproject/data_processor.py" ]; then
    cp "/home/ga/workspace/cleanup_imports_task/myproject/data_processor.py" "$RESULT_DIR/data_processor.py"
    echo "✅ Exported data_processor.py to $RESULT_DIR"
else
    echo "❌ ERROR: data_processor.py not found"
    exit 1
fi

echo "✅ Export complete"