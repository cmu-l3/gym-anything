#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Automate Build Workflow Result ==="

WORKSPACE_DIR="/home/ga/workspace/data_pipeline"
TASKS_JSON="$WORKSPACE_DIR/.vscode/tasks.json"

# Give time for any file operations to complete
sleep 2

# Try to save any open files
focus_vscode_window || true
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Could not send save command; continuing"
}

# Wait for tasks.json to be written if it exists
if [ -f "$TASKS_JSON" ]; then
    echo "tasks.json found, waiting for file sync..."
    sleep 2
fi

# Copy tasks.json to /tmp for verification
if [ -f "$TASKS_JSON" ]; then
    cp "$TASKS_JSON" /tmp/tasks.json 2>&1 || echo "{}" > /tmp/tasks.json
    echo "✅ tasks.json exported to /tmp"
    echo "Content preview:"
    head -20 "$TASKS_JSON" || true
else
    echo "⚠️ tasks.json not found at $TASKS_JSON"
    echo "{}" > /tmp/tasks.json
fi

# Also export directory listing for debugging
ls -la "$WORKSPACE_DIR/.vscode/" > /tmp/vscode_dir_listing.txt 2>&1 || echo "No .vscode directory" > /tmp/vscode_dir_listing.txt

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"