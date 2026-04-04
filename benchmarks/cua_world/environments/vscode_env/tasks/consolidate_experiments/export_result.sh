#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Consolidate Experiments Result ==="

WORKSPACE_DIR="/home/ga/workspace/api_middleware"

# Focus VSCode and save all files
focus_vscode_window
{
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
} || {
    echo "⚠️ Failed to save all files; continuing"
}

sleep 2

# Export file listing to /tmp
echo "Exporting file listing..."
ls -la "$WORKSPACE_DIR" > /tmp/workspace_files.txt 2>&1 || echo "Directory not found" > /tmp/workspace_files.txt

# Export git log
if [ -d "$WORKSPACE_DIR/.git" ]; then
    echo "Exporting git log..."
    cd "$WORKSPACE_DIR"
    sudo -u ga git log --all --format="%H|%s|%an|%ad" > /tmp/git_log.txt 2>&1 || echo "No commits" > /tmp/git_log.txt
    
    echo "Exporting git status..."
    sudo -u ga git status --porcelain > /tmp/git_status.txt 2>&1 || echo "" > /tmp/git_status.txt
else
    echo "No git repository" > /tmp/git_log.txt
    echo "" > /tmp/git_status.txt
fi

# Copy final rate_limiter.py if exists (for content verification)
if [ -f "$WORKSPACE_DIR/rate_limiter.py" ]; then
    echo "Copying final rate_limiter.py..."
    sudo -u ga cp "$WORKSPACE_DIR/rate_limiter.py" /tmp/rate_limiter_final.py 2>&1 || true
else
    echo "# File not found" > /tmp/rate_limiter_final.py
fi

# Copy requirements.txt if exists
if [ -f "$WORKSPACE_DIR/requirements.txt" ]; then
    echo "Copying requirements.txt..."
    sudo -u ga cp "$WORKSPACE_DIR/requirements.txt" /tmp/requirements_final.txt 2>&1 || true
else
    echo "# File not found" > /tmp/requirements_final.txt
fi

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"