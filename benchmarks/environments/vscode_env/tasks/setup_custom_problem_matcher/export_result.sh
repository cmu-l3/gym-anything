#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Custom Problem Matcher Result ==="

WORKSPACE_DIR="/home/ga/workspace/embedded_project"

# Give VSCode time to save any open files
sleep 2

# Try to save all files in VSCode
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 100 ctrl+shift+s
    sleep 1
} || {
    echo "⚠️ Failed to trigger save all; continuing"
}

# Wait for tasks.json to be written
wait_for_file "$WORKSPACE_DIR/.vscode/tasks.json" 2 || true

# Export tasks.json if it exists
if [ -f "$WORKSPACE_DIR/.vscode/tasks.json" ]; then
    echo "Exporting tasks.json..."
    cp "$WORKSPACE_DIR/.vscode/tasks.json" /tmp/tasks.json
    echo "✅ tasks.json exported to /tmp"
else
    echo "⚠️ tasks.json not found"
    echo "{}" > /tmp/tasks.json
fi

# Export CONTRIBUTING.md if it exists
if [ -f "$WORKSPACE_DIR/CONTRIBUTING.md" ]; then
    echo "Exporting CONTRIBUTING.md..."
    cp "$WORKSPACE_DIR/CONTRIBUTING.md" /tmp/contributing.md
    echo "✅ CONTRIBUTING.md exported to /tmp"
else
    echo "⚠️ CONTRIBUTING.md not found"
    echo "" > /tmp/contributing.md
fi

# Export directory listing for diagnostics
ls -la "$WORKSPACE_DIR/.vscode/" > /tmp/vscode_dir_list.txt 2>&1 || echo "No .vscode directory" > /tmp/vscode_dir_list.txt

echo "✅ Export complete"
echo "Files exported:"
echo "  - /tmp/tasks.json"
echo "  - /tmp/contributing.md"
echo "  - /tmp/vscode_dir_list.txt"