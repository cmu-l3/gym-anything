#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Reorganize Project Structure Result ==="

WORKSPACE_DIR="/home/ga/workspace/messy_project"

# Focus VSCode and save all files
focus_vscode_window
sleep 1

echo "Saving all open files..."
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to send save commands; continuing"
}

sleep 2

# Export directory structure
echo "Exporting directory structure..."
if [ -d "$WORKSPACE_DIR" ]; then
    # Create directory tree structure
    cd "$WORKSPACE_DIR"
    find . -type f -o -type d | sort > /tmp/project_structure.txt 2>&1 || echo "" > /tmp/project_structure.txt
    
    # List all files with their paths
    find . -type f | sort > /tmp/project_files.txt 2>&1 || echo "" > /tmp/project_files.txt
    
    # Export content of key files for verification
    echo "Exporting file contents for verification..."
    
    # Export src/app.py if exists
    if [ -f "$WORKSPACE_DIR/src/app.py" ]; then
        cp "$WORKSPACE_DIR/src/app.py" /tmp/app_py_content.txt 2>&1 || echo "" > /tmp/app_py_content.txt
    else
        echo "" > /tmp/app_py_content.txt
    fi
    
    # Export tests/test_app.py if exists
    if [ -f "$WORKSPACE_DIR/tests/test_app.py" ]; then
        cp "$WORKSPACE_DIR/tests/test_app.py" /tmp/test_app_py_content.txt 2>&1 || echo "" > /tmp/test_app_py_content.txt
    else
        echo "" > /tmp/test_app_py_content.txt
    fi
    
    echo "✅ Project structure exported"
else
    echo "⚠️ Workspace directory not found"
    echo "" > /tmp/project_structure.txt
    echo "" > /tmp/project_files.txt
fi

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"