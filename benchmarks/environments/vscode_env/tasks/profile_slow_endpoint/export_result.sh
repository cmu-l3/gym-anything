#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Profile Slow Endpoint Result ==="

# Focus VSCode and save all files
focus_vscode_window
{
    echo "Saving all files..."
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to save files via GUI; continuing"
}

sleep 2

# Wait for key files to be written
wait_for_file "/home/ga/workspace/PERFORMANCE.md" 3 || echo "⚠️ PERFORMANCE.md not updated"

echo "✅ Export complete"
echo "Files to verify:"
echo "  - /home/ga/workspace/profile_results.txt"
echo "  - /home/ga/workspace/PERFORMANCE.md"
echo "  - /home/ga/workspace/src/utils/external_api.py"