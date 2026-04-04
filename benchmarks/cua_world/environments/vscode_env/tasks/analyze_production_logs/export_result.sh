#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Production Log Analysis Result ==="

WORKSPACE_DIR="/home/ga/workspace"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to trigger save; continuing"
}

sleep 2

# Wait for the target file to be written
wait_for_file "$WORKSPACE_DIR/src/payment_processor.py" 5

# Copy the modified payment_processor.py to /tmp for verification
echo "Exporting modified source file..."
cp "$WORKSPACE_DIR/src/payment_processor.py" /tmp/payment_processor.py 2>/dev/null || \
    echo "⚠️ Warning: Could not copy payment_processor.py"

# Export list of recently opened files
echo "Exporting VSCode history..."
ls -lt "$WORKSPACE_DIR/src/" > /tmp/src_files_list.txt 2>/dev/null || echo "" > /tmp/src_files_list.txt

echo "✅ Export complete"
echo "Modified file: $WORKSPACE_DIR/src/payment_processor.py"
echo "Exported to: /tmp/payment_processor.py"