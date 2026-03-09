#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Prepare Async Workshop Result ==="

WORKSHOP_DIR="/home/ga/workshop"

# Focus VSCode and attempt to save all open files
focus_vscode_window
sleep 1

echo "Saving all open files..."
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 2
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to send save commands; continuing"
}

sleep 2

# Wait for critical files to be written
echo "Waiting for files to be written..."
wait_for_file "$WORKSHOP_DIR/package.json" 3 || true

# List the created files for debugging
echo ""
echo "Workshop directory contents:"
ls -la "$WORKSHOP_DIR" 2>&1 || echo "Workshop directory not accessible"

echo ""
echo "Checking for .vscode/ configuration:"
ls -la "$WORKSHOP_DIR/.vscode/" 2>&1 || echo ".vscode/ directory not found"

echo ""
echo "Checking JavaScript files:"
ls -1 "$WORKSHOP_DIR"/*.js 2>&1 || echo "No JavaScript files found"

echo ""
echo "✅ Export complete"
echo "Files should be available at: $WORKSHOP_DIR"