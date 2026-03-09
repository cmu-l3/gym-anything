#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Document Utility Functions Result ==="

# Focus VSCode and save file
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to save file; continuing"
}

# Wait for file to be written
wait_for_file "/home/ga/workspace/utils/helpers.ts" 5

# Copy the file to /tmp for verification
cp /home/ga/workspace/utils/helpers.ts /tmp/helpers.ts 2>/dev/null || echo "Failed to copy helpers.ts"

echo "✅ Export complete"
echo "File: /home/ga/workspace/utils/helpers.ts"