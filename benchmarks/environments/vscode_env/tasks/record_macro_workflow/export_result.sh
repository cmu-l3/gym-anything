#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Record Macro Workflow Result ==="

WORKSPACE_DIR="/home/ga/workspace/macro_task"
FILE_PATH="$WORKSPACE_DIR/data_processors.py"

# Try to focus VSCode and save the file
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to send save command; file may already be saved"
}

# Wait for file to be written
wait_for_file "$FILE_PATH" 5

# Copy file to /tmp for verifier access
if [ -f "$FILE_PATH" ]; then
    cp "$FILE_PATH" /tmp/data_processors.py
    echo "✅ Copied data_processors.py to /tmp"
    
    # Show first few lines for debugging
    echo "First 20 lines of file:"
    head -n 20 "$FILE_PATH"
else
    echo "⚠️ Warning: File not found at $FILE_PATH"
    echo "" > /tmp/data_processors.py
fi

echo "✅ Export complete"