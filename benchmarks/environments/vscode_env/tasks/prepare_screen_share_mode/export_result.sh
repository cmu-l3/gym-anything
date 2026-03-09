#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Screen Share Preparation Result ==="

# Focus VSCode and give time for auto-save
focus_vscode_window
sleep 2

# Wait for settings to be saved
wait_for_file "/home/ga/.config/Code/User/settings.json" 5

# Export settings.json to /tmp for verification
echo "Exporting settings.json..."
if [ -f "/home/ga/.config/Code/User/settings.json" ]; then
    cp "/home/ga/.config/Code/User/settings.json" /tmp/vscode_settings.json
    echo "✅ Settings exported to /tmp/vscode_settings.json"
else
    echo "⚠️ Settings file not found"
    echo "{}" > /tmp/vscode_settings.json
fi

# Export list of files in workspace (to verify work files still exist)
echo "Exporting workspace file list..."
ls -1 /home/ga/workspace/screen_share_task/ > /tmp/workspace_files.txt 2>&1 || echo "" > /tmp/workspace_files.txt

# Take screenshot for debugging (optional)
echo "Taking screenshot..."
su - ga -c "DISPLAY=:1 import -window root /tmp/vscode_screenshot.png" 2>/dev/null || echo "Screenshot failed (optional)"

echo "✅ Export complete"
echo ""
echo "Exported files:"
echo "  - /tmp/vscode_settings.json (VSCode settings)"
echo "  - /tmp/workspace_files.txt (workspace contents)"
echo "  - /tmp/vscode_screenshot.png (screenshot)"