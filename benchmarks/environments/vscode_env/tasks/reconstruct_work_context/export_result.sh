#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Reconstruct Work Context Result ==="

WORKSPACE_DIR="/home/ga/workspace/myproject"

# Focus VSCode and save
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to save via VSCode; continuing"
}

# Wait for file to be written
sleep 2

# Export the WORK_CONTEXT.md file if it exists
if [ -f "$WORKSPACE_DIR/WORK_CONTEXT.md" ]; then
    echo "Found WORK_CONTEXT.md, copying to /tmp for verification..."
    cp "$WORKSPACE_DIR/WORK_CONTEXT.md" /tmp/work_context_result.md 2>&1 || echo "Failed to copy"
else
    echo "WORK_CONTEXT.md not found in workspace root"
    echo "NOT_FOUND" > /tmp/work_context_result.md
fi

# Export git status and diff for verification
cd "$WORKSPACE_DIR"
sudo -u ga git status > /tmp/git_status_final.txt 2>&1 || echo "Git status failed"
sudo -u ga git diff > /tmp/git_diff_final.txt 2>&1 || echo "Git diff failed"

# Export bash history to check if git commands were used
sudo -u ga bash -c "history" > /tmp/bash_history.txt 2>&1 || echo ""
# Also try reading from bash history file
if [ -f "/home/ga/.bash_history" ]; then
    tail -100 /home/ga/.bash_history > /tmp/bash_history_file.txt 2>&1 || echo ""
else
    echo "" > /tmp/bash_history_file.txt
fi

# List all files in workspace for debugging
ls -la "$WORKSPACE_DIR" > /tmp/workspace_listing.txt 2>&1 || echo "Failed to list"

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"
if [ -f "$WORKSPACE_DIR/WORK_CONTEXT.md" ]; then
    echo "WORK_CONTEXT.md file size: $(wc -c < $WORKSPACE_DIR/WORK_CONTEXT.md) bytes"
fi