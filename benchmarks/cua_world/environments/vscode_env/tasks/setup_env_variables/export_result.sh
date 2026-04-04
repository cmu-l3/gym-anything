#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Environment Variables Configuration Result ==="

WORKSPACE_DIR="/home/ga/workspace/env_task"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s  # Save All
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s  # Save current
} || {
    echo "⚠️ Failed to send save commands; continuing"
}

sleep 2

# Export .env file to /tmp (if exists)
if [ -f "$WORKSPACE_DIR/.env" ]; then
    echo "Exporting .env file..."
    cp "$WORKSPACE_DIR/.env" /tmp/result_env_file.txt 2>&1 || echo "Failed to copy .env"
else
    echo "⚠️ .env file not found"
    echo "FILE_NOT_FOUND" > /tmp/result_env_file.txt
fi

# Export launch.json to /tmp
if [ -f "$WORKSPACE_DIR/.vscode/launch.json" ]; then
    echo "Exporting launch.json..."
    cp "$WORKSPACE_DIR/.vscode/launch.json" /tmp/result_launch.json 2>&1 || echo "Failed to copy launch.json"
else
    echo "⚠️ launch.json not found"
    echo "FILE_NOT_FOUND" > /tmp/result_launch.json
fi

# Export .gitignore to /tmp
if [ -f "$WORKSPACE_DIR/.gitignore" ]; then
    echo "Exporting .gitignore..."
    cp "$WORKSPACE_DIR/.gitignore" /tmp/result_gitignore.txt 2>&1 || echo "Failed to copy .gitignore"
else
    echo "⚠️ .gitignore not found"
    echo "" > /tmp/result_gitignore.txt
fi

echo "✅ Export complete"
echo "Exported files:"
echo "  - /tmp/result_env_file.txt"
echo "  - /tmp/result_launch.json"
echo "  - /tmp/result_gitignore.txt"