#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Create FastAPI Scaffold Result ==="

WORKSPACE_DIR="/home/ga/workspace/notification_service"

# Focus VSCode and save all files
echo "Saving all files..."
focus_vscode_window
sleep 1

# Save all open files
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+shift+s" || {
    echo "⚠️ Ctrl+Shift+S failed, trying Ctrl+K S"
    su - ga -c "DISPLAY=:1 xdotool key --delay 100 ctrl+k s" || true
}

sleep 2

# Also try individual save
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+s" || true
sleep 1

# Wait a moment for file system sync
sync
sleep 1

# List created files for debugging
if [ -d "$WORKSPACE_DIR" ]; then
    echo "📁 Workspace contents:"
    find "$WORKSPACE_DIR" -type f -o -type d | head -20
    
    echo ""
    echo "📊 File count: $(find "$WORKSPACE_DIR" -type f | wc -l) files"
    echo "📊 Directory count: $(find "$WORKSPACE_DIR" -type d | wc -l) directories"
else
    echo "⚠️ Warning: Workspace directory not found"
fi

echo "✅ Export complete"