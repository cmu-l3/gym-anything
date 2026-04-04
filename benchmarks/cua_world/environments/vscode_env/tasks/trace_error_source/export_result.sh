#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Trace Error Source Result ==="

WORKSPACE_DIR="/home/ga/workspace/user_service"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to send save commands; continuing"
}

# Wait for files to be written
sleep 2

# Copy files to /tmp for verification
echo "Copying files for verification..."
sudo -u ga cp "$WORKSPACE_DIR/data_processor.py" /tmp/data_processor.py 2>/dev/null || echo "data_processor.py not found"
sudo -u ga cp "$WORKSPACE_DIR/investigation_notes.md" /tmp/investigation_notes.md 2>/dev/null || echo "investigation_notes.md not found"

# List workspace contents
echo "Workspace contents:"
ls -la "$WORKSPACE_DIR"

echo "✅ Export complete"