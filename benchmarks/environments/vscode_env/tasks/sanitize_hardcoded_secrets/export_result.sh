#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Sanitize Hardcoded Secrets Result ==="

WORKSPACE_DIR="/home/ga/workspace/payment_service"

# Focus VSCode and attempt to save all
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to trigger save; continuing"
}

sleep 2

# Wait for key files
wait_for_file "$WORKSPACE_DIR/app.py" 3
wait_for_file "$WORKSPACE_DIR/db_connector.py" 3
wait_for_file "$WORKSPACE_DIR/payment_handler.py" 3
wait_for_file "$WORKSPACE_DIR/.gitignore" 3

# Export all relevant files to /tmp for verification
echo "Exporting modified source files..."
cp "$WORKSPACE_DIR/app.py" /tmp/app.py 2>/dev/null || echo "MISSING" > /tmp/app.py
cp "$WORKSPACE_DIR/db_connector.py" /tmp/db_connector.py 2>/dev/null || echo "MISSING" > /tmp/db_connector.py
cp "$WORKSPACE_DIR/payment_handler.py" /tmp/payment_handler.py 2>/dev/null || echo "MISSING" > /tmp/payment_handler.py

# Export .env file (should exist if task was done correctly)
if [ -f "$WORKSPACE_DIR/.env" ]; then
    cp "$WORKSPACE_DIR/.env" /tmp/.env
    echo "✅ .env file found and exported"
else
    echo "NO_ENV_FILE" > /tmp/.env
    echo "⚠️ .env file not found"
fi

# Export .gitignore
cp "$WORKSPACE_DIR/.gitignore" /tmp/.gitignore 2>/dev/null || echo "MISSING" > /tmp/.gitignore

# Export Git status to check if .env is staged
cd "$WORKSPACE_DIR"
if [ -d .git ]; then
    sudo -u ga git status --porcelain > /tmp/git_status.txt 2>&1 || echo "" > /tmp/git_status.txt
    sudo -u ga git diff --cached > /tmp/git_staged.txt 2>&1 || echo "" > /tmp/git_staged.txt
    
    # Check if .env is tracked
    sudo -u ga git ls-files .env > /tmp/git_tracked_env.txt 2>&1 || echo "" > /tmp/git_tracked_env.txt
else
    echo "" > /tmp/git_status.txt
    echo "" > /tmp/git_staged.txt
    echo "" > /tmp/git_tracked_env.txt
fi

echo "✅ Export complete"
echo "Files exported to /tmp/"