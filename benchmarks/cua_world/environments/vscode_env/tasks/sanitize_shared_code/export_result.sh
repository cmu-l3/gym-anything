#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Sanitize Shared Code Result ==="

WORKSPACE_DIR="/home/ga/workspace/flask_demo"

# Focus VSCode and save all files
focus_vscode_window
sleep 1

# Save all open files (Ctrl+K S or Ctrl+Shift+S)
{
    safe_xdotool ga :1 key --delay 200 ctrl+k s
} || {
    echo "⚠️ First save attempt failed, trying alternative..."
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
} || {
    echo "⚠️ Save shortcuts failed; continuing anyway"
}

sleep 2

# Wait for key files to be present
wait_for_file "$WORKSPACE_DIR/app.py" 5
wait_for_file "$WORKSPACE_DIR/config.py" 5
wait_for_file "$WORKSPACE_DIR/test_app.py" 5

# Export file contents to /tmp for verification
echo "Exporting file contents to /tmp..."
cp "$WORKSPACE_DIR/app.py" /tmp/sanitized_app.py 2>/dev/null || echo "Warning: Could not copy app.py"
cp "$WORKSPACE_DIR/config.py" /tmp/sanitized_config.py 2>/dev/null || echo "Warning: Could not copy config.py"
cp "$WORKSPACE_DIR/test_app.py" /tmp/sanitized_test_app.py 2>/dev/null || echo "Warning: Could not copy test_app.py"

# Copy documentation if it exists
if [ -f "$WORKSPACE_DIR/SECRETS_REMOVED.md" ]; then
    cp "$WORKSPACE_DIR/SECRETS_REMOVED.md" /tmp/SECRETS_REMOVED.md
    echo "✅ SECRETS_REMOVED.md found and exported"
else
    echo "" > /tmp/SECRETS_REMOVED.md
    echo "⚠️ SECRETS_REMOVED.md not found"
fi

# List workspace contents
echo "Workspace contents:"
ls -la "$WORKSPACE_DIR/"

echo "✅ Export complete"
echo "Files exported to /tmp for verification"