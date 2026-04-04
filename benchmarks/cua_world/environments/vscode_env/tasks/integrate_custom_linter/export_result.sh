#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Integrate Custom Linter Result ==="

WORKSPACE_DIR="/home/ga/workspace/medscan_project"

# Focus VSCode and save any open files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to save files; continuing"
}

sleep 1

# Wait for tasks.json to be created
wait_for_file "$WORKSPACE_DIR/.vscode/tasks.json" 5 || echo "⚠️ tasks.json not created yet"

# Export tasks.json to /tmp for verification
if [ -f "$WORKSPACE_DIR/.vscode/tasks.json" ]; then
    echo "Exporting tasks.json..."
    cp "$WORKSPACE_DIR/.vscode/tasks.json" /tmp/tasks.json 2>&1 || echo "Failed to copy tasks.json"
    echo "✅ tasks.json exported to /tmp"
else
    echo "⚠️ tasks.json not found at $WORKSPACE_DIR/.vscode/tasks.json"
    echo "{}" > /tmp/tasks.json
fi

# Export directory listing for debugging
ls -la "$WORKSPACE_DIR/.vscode/" > /tmp/vscode_dir_listing.txt 2>&1 || echo "No .vscode directory" > /tmp/vscode_dir_listing.txt

echo "✅ Export complete"