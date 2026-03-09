#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Instrument API Logging Result ==="

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s  # Save All
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s  # Save current
} || {
    echo "⚠️ Failed to trigger save; continuing"
}

sleep 2

# Wait for files to be saved
wait_for_file "/home/ga/workspace/api_logging/app.py" 5

# Copy files to /tmp for verifier
WORKSPACE_DIR="/home/ga/workspace/api_logging"

echo "Copying modified files to /tmp..."
cp "$WORKSPACE_DIR/app.py" /tmp/app.py 2>&1 || echo "" > /tmp/app.py

# Check if logging_config.py was created
if [ -f "$WORKSPACE_DIR/logging_config.py" ]; then
    echo "Found logging_config.py, copying..."
    cp "$WORKSPACE_DIR/logging_config.py" /tmp/logging_config.py
else
    echo "No logging_config.py found (optional)"
    echo "" > /tmp/logging_config.py
fi

# Check if middleware.py was created
if [ -f "$WORKSPACE_DIR/middleware.py" ]; then
    echo "Found middleware.py, copying..."
    cp "$WORKSPACE_DIR/middleware.py" /tmp/middleware.py
else
    echo "No middleware.py found (optional)"
    echo "" > /tmp/middleware.py
fi

echo "✅ Export complete"
echo "Files exported to /tmp:"
ls -lh /tmp/app.py /tmp/logging_config.py /tmp/middleware.py 2>&1 || true