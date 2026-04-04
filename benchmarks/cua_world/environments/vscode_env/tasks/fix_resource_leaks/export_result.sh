#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Fix Resource Leaks Result ==="

# Focus VSCode and save all files
focus_vscode_window
sleep 1

# Save all files (Ctrl+K S)
echo "Saving all files..."
safe_xdotool ga :1 key --delay 100 ctrl+k
sleep 0.5
safe_xdotool ga :1 key --delay 100 s
sleep 2

# Wait for files to be written
echo "Waiting for file writes to complete..."
sleep 2

# Copy files to /tmp for verification
WORKSPACE_DIR="/home/ga/workspace/flask_api"
TMP_DIR="/tmp/flask_api_result"
mkdir -p "$TMP_DIR"

echo "Copying modified files to $TMP_DIR..."
cp "$WORKSPACE_DIR/app.py" "$TMP_DIR/" 2>/dev/null || echo "app.py not found"
cp "$WORKSPACE_DIR/db.py" "$TMP_DIR/" 2>/dev/null || echo "db.py not found"
cp "$WORKSPACE_DIR/file_processor.py" "$TMP_DIR/" 2>/dev/null || echo "file_processor.py not found"
cp "$WORKSPACE_DIR/report_generator.py" "$TMP_DIR/" 2>/dev/null || echo "report_generator.py not found"
cp "$WORKSPACE_DIR/backup.py" "$TMP_DIR/" 2>/dev/null || echo "backup.py not found"

echo "✅ Export complete"
echo "Files exported to: $TMP_DIR"
ls -la "$TMP_DIR/"