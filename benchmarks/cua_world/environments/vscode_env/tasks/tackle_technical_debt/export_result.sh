#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Tackle Technical Debt Result ==="

WORKSPACE_DIR="/home/ga/workspace/webservice"

# Focus VSCode and save all files
focus_vscode_window
sleep 1

# Save all open files (Ctrl+K S is Save All in VSCode)
{
    safe_xdotool ga :1 key --delay 200 ctrl+k s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to save files via xdotool; continuing"
}

sleep 2

# Wait for key files to be written
wait_for_file "$WORKSPACE_DIR/routes/users.py" 5
wait_for_file "$WORKSPACE_DIR/database.py" 5
wait_for_file "$WORKSPACE_DIR/utils.py" 5

# Copy files to /tmp for easier verifier access
echo "Copying files to /tmp for verification..."
cp "$WORKSPACE_DIR/routes/users.py" /tmp/users.py 2>/dev/null || true
cp "$WORKSPACE_DIR/database.py" /tmp/database.py 2>/dev/null || true
cp "$WORKSPACE_DIR/utils.py" /tmp/utils.py 2>/dev/null || true
cp "$WORKSPACE_DIR/CHANGELOG.md" /tmp/CHANGELOG.md 2>/dev/null || true

# Export git status
cd "$WORKSPACE_DIR"
sudo -u ga git status --porcelain > /tmp/git_status.txt 2>&1 || echo "" > /tmp/git_status.txt
sudo -u ga git diff > /tmp/git_diff.txt 2>&1 || echo "" > /tmp/git_diff.txt

echo "✅ Export complete"
echo "Files exported to /tmp/"