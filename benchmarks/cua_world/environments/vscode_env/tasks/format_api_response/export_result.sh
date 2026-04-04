#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Format API Response Result ==="

# Focus VSCode and save all files
focus_vscode_window
{
    # Save current file
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
    # Save all files
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
} || {
    echo "⚠️ Failed to send save commands; continuing"
}

# Wait for files to be written
WORKSPACE_DIR="/home/ga/workspace/api_project"
wait_for_file "$WORKSPACE_DIR/api_response.json" 5
wait_for_file "$WORKSPACE_DIR/price_summary.json" 3 || echo "price_summary.json may not exist yet"
wait_for_file "$WORKSPACE_DIR/API_STRUCTURE.md" 3 || echo "API_STRUCTURE.md may not exist yet"

# Export file metadata to /tmp for debugging
echo "Exporting file information..."
ls -lah "$WORKSPACE_DIR/" > /tmp/api_files_list.txt 2>&1 || echo "Failed to list files" > /tmp/api_files_list.txt

# Count lines in api_response.json to check if formatted
wc -l "$WORKSPACE_DIR/api_response.json" > /tmp/api_response_lines.txt 2>&1 || echo "0" > /tmp/api_response_lines.txt

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"