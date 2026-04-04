#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting VSCode Task Automation Result ==="

WORKSPACE_DIR="/home/ga/workspace/sales_analysis"
TASKS_JSON="${WORKSPACE_DIR}/.vscode/tasks.json"
EXPORT_DIR="/tmp/task_automation_export"

# Create export directory
mkdir -p "$EXPORT_DIR"

# Try to save any open files in VSCode
echo "Attempting to save files in VSCode..."
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Could not send save command; continuing"
}

# Wait a moment for files to be written
sleep 2

# Export tasks.json if it exists
if [ -f "$TASKS_JSON" ]; then
    cp "$TASKS_JSON" "$EXPORT_DIR/tasks.json"
    echo "✅ tasks.json copied to export directory"
    echo "Content preview:"
    head -20 "$TASKS_JSON"
else
    echo "⚠️ tasks.json not found at $TASKS_JSON"
    echo "NOT_FOUND" > "$EXPORT_DIR/tasks.json"
fi

# Export entire .vscode directory structure for inspection
if [ -d "${WORKSPACE_DIR}/.vscode" ]; then
    cp -r "${WORKSPACE_DIR}/.vscode" "$EXPORT_DIR/vscode_dir"
    echo "✅ .vscode directory copied"
    ls -la "${WORKSPACE_DIR}/.vscode/"
else
    echo "⚠️ .vscode directory not found"
    echo "DIRECTORY_NOT_FOUND" > "$EXPORT_DIR/vscode_status.txt"
fi

# List workspace contents for debugging
echo ""
echo "Workspace contents:"
ls -la "$WORKSPACE_DIR"

# Take screenshot
echo "Taking screenshot..."
su - ga -c "DISPLAY=:1 import -window root $EXPORT_DIR/final_screenshot.png 2>/dev/null" || echo "Screenshot failed"

echo ""
echo "✅ Export complete"
echo "Export directory: $EXPORT_DIR"
ls -la "$EXPORT_DIR"