#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Add Type Hints Result ==="

# Focus VSCode and save
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to save; continuing"
}

# Wait for file to be written
sleep 2
wait_for_file "/home/ga/workspace/type_hints_project/data_processor.py" 5

# Copy file to /tmp for easier verification access
cp "/home/ga/workspace/type_hints_project/data_processor.py" /tmp/data_processor_result.py 2>/dev/null || true

echo "✅ Export complete"
echo "File: /home/ga/workspace/type_hints_project/data_processor.py"