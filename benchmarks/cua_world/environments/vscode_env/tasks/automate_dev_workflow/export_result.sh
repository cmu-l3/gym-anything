#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Automate Dev Workflow Result ==="

WORKSPACE_DIR="/home/ga/dev-project"
TASKS_JSON="$WORKSPACE_DIR/.vscode/tasks.json"

# Focus VSCode and save all files
focus_vscode_window
sleep 1

# Save all files
echo "Saving all files..."
su - ga -c "DISPLAY=:1 xdotool key --delay 100 ctrl+shift+s" || true
sleep 2

# Also try regular save
su - ga -c "DISPLAY=:1 xdotool key --delay 100 ctrl+s" || true
sleep 1

# Wait for tasks.json to be written
if [ -f "$TASKS_JSON" ]; then
    echo "✓ tasks.json file detected"
    # Give it a moment to finish writing
    sleep 1
else
    echo "⚠ tasks.json not found yet, waiting..."
    sleep 2
fi

# Export tasks.json to /tmp for verification
if [ -f "$TASKS_JSON" ]; then
    echo "Exporting tasks.json..."
    cp "$TASKS_JSON" /tmp/tasks.json
    echo "✓ tasks.json exported to /tmp/tasks.json"
    echo "Content preview:"
    head -20 /tmp/tasks.json
else
    echo "⚠ Warning: tasks.json not found at $TASKS_JSON"
    echo "{}" > /tmp/tasks.json
fi

# Also export the entire .vscode directory for debugging
if [ -d "$WORKSPACE_DIR/.vscode" ]; then
    echo "Exporting .vscode directory..."
    mkdir -p /tmp/vscode-backup
    cp -r "$WORKSPACE_DIR/.vscode"/* /tmp/vscode-backup/ 2>/dev/null || true
    echo "✓ .vscode directory backed up"
fi

# List workspace structure for debugging
echo ""
echo "Workspace structure:"
ls -la "$WORKSPACE_DIR/" 2>/dev/null || echo "Workspace not found"
if [ -d "$WORKSPACE_DIR/.vscode" ]; then
    echo ""
    echo ".vscode directory contents:"
    ls -la "$WORKSPACE_DIR/.vscode/" 2>/dev/null || echo ".vscode empty"
fi

echo "✅ Export complete"
echo "Expected file: $TASKS_JSON"