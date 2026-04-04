#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Fix Encoding Issues Result ==="

# Focus VSCode and save all files
focus_vscode_window
sleep 1

# Save all files (Ctrl+K, S)
echo "Saving all files..."
{
    su - ga -c "DISPLAY=:1 xdotool key --delay 150 ctrl+k s" || true
    sleep 1
    # Also try Ctrl+Shift+S (Save All) as fallback
    su - ga -c "DISPLAY=:1 xdotool key --delay 150 ctrl+shift+s" || true
} 2>/dev/null

sleep 2

# Wait for key files to be written
wait_for_file "/home/ga/workspace/data-pipeline/data/customers.csv" 3
wait_for_file "/home/ga/workspace/data-pipeline/README.md" 3

echo "✅ Export complete"
echo "Files should be saved with correct encoding and line endings"