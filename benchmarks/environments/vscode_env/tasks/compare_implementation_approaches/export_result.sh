#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Compare Implementation Approaches Result ==="

WORKSPACE_DIR="/home/ga/workspace/data_pipeline"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
} || {
    echo "⚠️ Failed to focus VSCode window; continuing"
}

# Wait for files to be written
sleep 2

# List files in workspace for debugging
echo "Files in workspace:"
ls -la "$WORKSPACE_DIR"/ 2>&1 || echo "Workspace not found"

# Export file list to /tmp for verifier
ls -1 "$WORKSPACE_DIR"/ > /tmp/workspace_files.txt 2>&1 || echo "" > /tmp/workspace_files.txt

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"