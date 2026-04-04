#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Jump to Line Navigation Result ==="

# Focus VSCode and save file
focus_vscode_window
sleep 1

# Send Ctrl+S to save file
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to trigger save; continuing"
}

# Wait for file to be written
sleep 2

WORKSPACE_FILE="/home/ga/workspace/line_nav_task/main.py"

# Verify file exists before exporting
if [ -f "$WORKSPACE_FILE" ]; then
    # Copy file to /tmp for verification
    cp "$WORKSPACE_FILE" /tmp/main_py_result.txt 2>&1 || echo "Failed to copy file"
    
    # Extract line 342 specifically for quick verification
    sed -n '342p' "$WORKSPACE_FILE" > /tmp/line_342_content.txt 2>&1 || echo "" > /tmp/line_342_content.txt
    
    # Count total lines
    wc -l "$WORKSPACE_FILE" > /tmp/file_line_count.txt 2>&1 || echo "0" > /tmp/file_line_count.txt
    
    echo "✅ File exported successfully"
    echo "Line 342 content: $(cat /tmp/line_342_content.txt)"
else
    echo "⚠️ Warning: File not found at $WORKSPACE_FILE"
    echo "" > /tmp/main_py_result.txt
    echo "" > /tmp/line_342_content.txt
    echo "0" > /tmp/file_line_count.txt
fi

echo "✅ Export complete"