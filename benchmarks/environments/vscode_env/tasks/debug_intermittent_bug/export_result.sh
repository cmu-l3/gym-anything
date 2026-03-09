#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Debug Intermittent Bug Result ==="

WORKSPACE_DIR="/home/ga/workspace/api_service"

# Focus VSCode and save all files
focus_vscode_window
sleep 1

# Save all open files
echo "Saving all files..."
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to send save commands; continuing"
}

sleep 2

# Wait for critical files to be written
wait_for_file "$WORKSPACE_DIR/lib/database.js" 3

# Copy modified files to /tmp for verification
echo "Copying files for verification..."
cp "$WORKSPACE_DIR/lib/database.js" /tmp/database.js 2>/dev/null || echo "database.js not found"
cp "$WORKSPACE_DIR/DEBUGGING_NOTES.md" /tmp/DEBUGGING_NOTES.md 2>/dev/null || echo "DEBUGGING_NOTES.md not found"
cp "$WORKSPACE_DIR/server.js" /tmp/server.js 2>/dev/null || echo "server.js not modified"

# List workspace contents for debugging
echo "Workspace contents:"
ls -la "$WORKSPACE_DIR/" 2>&1 | head -n 20

echo "✅ Export complete"
echo "Modified files copied to /tmp for verification"