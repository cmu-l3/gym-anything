#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Navigate Back After Definition Result ==="

# Try to save current file
focus_vscode_window
{
    su - ga -c "DISPLAY=:1 xdotool key --delay 100 ctrl+s" || true
} 2>/dev/null
sleep 1

WORKSPACE_DIR="/home/ga/workspace/nav_task"

# Export file contents
if [ -f "$WORKSPACE_DIR/main.py" ]; then
    cp "$WORKSPACE_DIR/main.py" /tmp/nav_task_main_final.py
    echo "✅ Exported main.py"
else
    echo "⚠️ main.py not found"
    echo "" > /tmp/nav_task_main_final.py
fi

if [ -f "$WORKSPACE_DIR/utils/helpers.py" ]; then
    cp "$WORKSPACE_DIR/utils/helpers.py" /tmp/nav_task_helpers_final.py
    echo "✅ Exported helpers.py"
else
    echo "⚠️ helpers.py not found"
    echo "" > /tmp/nav_task_helpers_final.py
fi

# Try to detect active file by checking window title
su - ga -c "DISPLAY=:1 xdotool getactivewindow getwindowname" > /tmp/nav_task_window_title.txt 2>&1 || echo "unknown" > /tmp/nav_task_window_title.txt

# Export VSCode workspace state if available
WORKSPACE_STATE_DIR="/home/ga/.config/Code/User/workspaceStorage"
if [ -d "$WORKSPACE_STATE_DIR" ]; then
    # Find the most recently modified workspace state
    RECENT_WORKSPACE=$(find "$WORKSPACE_STATE_DIR" -name "workspace.json" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    if [ -n "$RECENT_WORKSPACE" ] && [ -f "$RECENT_WORKSPACE" ]; then
        cp "$RECENT_WORKSPACE" /tmp/nav_task_workspace_state.json 2>/dev/null || echo "{}" > /tmp/nav_task_workspace_state.json
    else
        echo "{}" > /tmp/nav_task_workspace_state.json
    fi
else
    echo "{}" > /tmp/nav_task_workspace_state.json
fi

# Check which file was accessed more recently (heuristic for active file)
MAIN_TIME=$(stat -c %Y "$WORKSPACE_DIR/main.py" 2>/dev/null || echo "0")
HELPERS_TIME=$(stat -c %Y "$WORKSPACE_DIR/utils/helpers.py" 2>/dev/null || echo "0")

echo "$MAIN_TIME" > /tmp/nav_task_main_access_time.txt
echo "$HELPERS_TIME" > /tmp/nav_task_helpers_access_time.txt

# Try to get list of open files from VSCode
su - ga -c "DISPLAY=:1 xdotool search --class 'Code' getwindowname 2>/dev/null" > /tmp/nav_task_vscode_windows.txt || echo "" > /tmp/nav_task_vscode_windows.txt

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"