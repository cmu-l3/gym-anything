#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Compare Implementations Result ==="

WORKSPACE_DIR="/home/ga/workspace"

# Give any file saves time to complete
sleep 2

# Try to save any open files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to save files; continuing"
}

# Wait for comparison notes file if it's being written
wait_for_file "$WORKSPACE_DIR/comparison_notes.txt" 3 || true

# Export file listing for verification
echo "Exporting file listing..."
ls -la "$WORKSPACE_DIR/" > /tmp/workspace_files.txt 2>&1 || echo "Error listing workspace" > /tmp/workspace_files.txt
ls -la "$WORKSPACE_DIR/pipelines/" > /tmp/pipelines_files.txt 2>&1 || echo "Error listing pipelines" > /tmp/pipelines_files.txt

# Take screenshot of VSCode for potential visual verification
echo "Capturing screenshot..."
su - ga -c "DISPLAY=:1 import -window root /tmp/vscode_comparison_screenshot.png" 2>/dev/null || {
    echo "⚠️ Screenshot capture failed (non-critical)"
}

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"
echo "Comparison notes: $WORKSPACE_DIR/comparison_notes.txt"

# Show comparison notes if they exist
if [ -f "$WORKSPACE_DIR/comparison_notes.txt" ]; then
    echo "=== Comparison Notes Content ==="
    cat "$WORKSPACE_DIR/comparison_notes.txt"
    echo "=== End of Comparison Notes ==="
fi