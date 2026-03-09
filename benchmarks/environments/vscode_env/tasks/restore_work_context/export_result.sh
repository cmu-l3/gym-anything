#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Restore Work Context Result ==="

# Give VSCode time to update state
sleep 2

# Focus VSCode and save any open files
focus_vscode_window || true
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
} || {
    echo "⚠️ Save all files command may have failed; continuing"
}

sleep 1

# Export VSCode window information
echo "Exporting window information..."
su - ga -c "DISPLAY=:1 wmctrl -l" > /tmp/window_list.txt 2>&1 || echo "No windows" > /tmp/window_list.txt

# Export list of processes to check VSCode is running
ps aux | grep -i "code" | grep -v grep > /tmp/vscode_processes.txt 2>&1 || echo "No VSCode processes" > /tmp/vscode_processes.txt

# Try to get list of open files from VSCode CLI (may not work reliably, but worth trying)
su - ga -c "DISPLAY=:1 code --status" > /tmp/vscode_status.txt 2>&1 || echo "Status unavailable" > /tmp/vscode_status.txt

# Check if target files exist and get their access times
stat /home/ga/projects/user-auth-service/app/routes/auth.py > /tmp/auth_stat.txt 2>&1 || echo "File not found" > /tmp/auth_stat.txt
stat /home/ga/projects/user-auth-service/app/services/email_service.py > /tmp/email_stat.txt 2>&1 || echo "File not found" > /tmp/email_stat.txt
stat /home/ga/projects/user-auth-service/app/models/user.py > /tmp/user_stat.txt 2>&1 || echo "File not found" > /tmp/user_stat.txt

# Try to export VSCode workspace storage (where open editors are tracked)
STORAGE_DIR="/home/ga/.config/Code/User/workspaceStorage"
if [ -d "$STORAGE_DIR" ]; then
    # Find the most recently modified workspace storage directory
    LATEST_WORKSPACE=$(ls -td "$STORAGE_DIR"/*/ 2>/dev/null | head -1)
    if [ -n "$LATEST_WORKSPACE" ] && [ -f "${LATEST_WORKSPACE}workspace.json" ]; then
        cp "${LATEST_WORKSPACE}workspace.json" /tmp/vscode_workspace_state.json 2>&1 || echo "{}" > /tmp/vscode_workspace_state.json
        echo "Workspace state copied from: $LATEST_WORKSPACE"
    else
        echo "{}" > /tmp/vscode_workspace_state.json
    fi
else
    echo "{}" > /tmp/vscode_workspace_state.json
fi

# Also try to get the state.vscdb (VSCode's state database - SQLite format)
# This contains open editors information
if [ -d "$STORAGE_DIR" ]; then
    LATEST_WORKSPACE=$(ls -td "$STORAGE_DIR"/*/ 2>/dev/null | head -1)
    if [ -n "$LATEST_WORKSPACE" ] && [ -f "${LATEST_WORKSPACE}state.vscdb" ]; then
        cp "${LATEST_WORKSPACE}state.vscdb" /tmp/vscode_state.vscdb 2>&1 || touch /tmp/vscode_state.vscdb
        echo "State DB copied from: $LATEST_WORKSPACE"
    else
        touch /tmp/vscode_state.vscdb
    fi
else
    touch /tmp/vscode_state.vscdb
fi

# Export recently accessed files list from VSCode User storage
RECENT_FILES="/home/ga/.config/Code/User/globalStorage/storage.json"
if [ -f "$RECENT_FILES" ]; then
    cp "$RECENT_FILES" /tmp/vscode_recent_files.json 2>&1 || echo "{}" > /tmp/vscode_recent_files.json
else
    echo "{}" > /tmp/vscode_recent_files.json
fi

echo "✅ Export complete"
echo "Workspace: /home/ga/projects/user-auth-service"
echo "Target files: auth.py, email_service.py, user.py"