#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Write Bug Reproduction Test Result ==="

# Focus VSCode and save
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to save file; continuing"
}

# Wait for test file to be written
wait_for_file "/home/ga/workspace/data-processor/tests/test_text_utils.py" 5

# Give time for any terminal commands to complete
sleep 2

echo "✅ Export complete"
echo "Test file: /home/ga/workspace/data-processor/tests/test_text_utils.py"