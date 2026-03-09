#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Interview Environment Result ==="

WORKSPACE_DIR="/home/ga/interview_workspace"

# Give time for any pending file saves
sleep 2

# Try to save all open files in VSCode
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
} || {
    echo "⚠️ Failed to trigger save all; continuing"
}

sleep 1

# Export workspace structure and files to /tmp for verification
echo "Exporting workspace structure..."

if [ -d "$WORKSPACE_DIR" ]; then
    # Create a manifest of the directory structure
    find "$WORKSPACE_DIR" -type f -o -type d > /tmp/workspace_structure.txt 2>&1 || echo "" > /tmp/workspace_structure.txt
    
    # Copy configuration files if they exist
    if [ -f "$WORKSPACE_DIR/.vscode/settings.json" ]; then
        cp "$WORKSPACE_DIR/.vscode/settings.json" /tmp/interview_settings.json 2>&1 || echo "{}" > /tmp/interview_settings.json
        echo "✅ Settings copied"
    else
        echo "{}" > /tmp/interview_settings.json
        echo "⚠️ Settings file not found"
    fi
    
    if [ -f "$WORKSPACE_DIR/.vscode/tasks.json" ]; then
        cp "$WORKSPACE_DIR/.vscode/tasks.json" /tmp/interview_tasks.json 2>&1 || echo "{}" > /tmp/interview_tasks.json
        echo "✅ Tasks copied"
    else
        echo "{}" > /tmp/interview_tasks.json
        echo "⚠️ Tasks file not found"
    fi
    
    # Copy starter files if they exist
    for file in "starter.py" "starter.js" "Starter.java"; do
        if [ -f "$WORKSPACE_DIR/$file" ]; then
            cp "$WORKSPACE_DIR/$file" "/tmp/interview_$file" 2>&1 || echo "" > "/tmp/interview_$file"
            echo "✅ $file copied"
        else
            echo "" > "/tmp/interview_$file"
            echo "⚠️ $file not found"
        fi
    done
    
    echo "✅ Workspace data exported to /tmp"
else
    echo "⚠️ Workspace directory not found at $WORKSPACE_DIR"
    echo "" > /tmp/workspace_structure.txt
    echo "{}" > /tmp/interview_settings.json
    echo "{}" > /tmp/interview_tasks.json
    for file in "starter.py" "starter.js" "Starter.java"; do
        echo "" > "/tmp/interview_$file"
    done
fi

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"