#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Code Coverage Visualization Result ==="

WORKSPACE_DIR="/home/ga/workspace/coverage_task"

# Give processes time to complete
sleep 2

# Export installed extensions list
echo "Exporting extensions list..."
su - ga -c "DISPLAY=:1 code --list-extensions > /tmp/coverage_extensions.txt 2>&1" || echo "" > /tmp/coverage_extensions.txt

# Export extensions directory listing
ls -la /home/ga/.vscode/extensions/ > /tmp/coverage_extensions_dir.txt 2>&1 || echo "No extensions directory" > /tmp/coverage_extensions_dir.txt

# Copy coverage files if they exist
if [ -f "$WORKSPACE_DIR/coverage.xml" ]; then
    echo "Copying coverage.xml..."
    cp "$WORKSPACE_DIR/coverage.xml" /tmp/coverage_result.xml 2>&1 || echo "Failed to copy coverage.xml"
elif [ -f "$WORKSPACE_DIR/lcov.info" ]; then
    echo "Copying lcov.info..."
    cp "$WORKSPACE_DIR/lcov.info" /tmp/coverage_result.lcov 2>&1 || echo "Failed to copy lcov.info"
elif [ -f "$WORKSPACE_DIR/.coverage" ]; then
    echo "Copying .coverage..."
    cp "$WORKSPACE_DIR/.coverage" /tmp/coverage_result.coverage 2>&1 || echo "Failed to copy .coverage"
else
    echo "No coverage file found" > /tmp/coverage_result.txt
fi

# Copy workspace settings if they exist
if [ -f "$WORKSPACE_DIR/.vscode/settings.json" ]; then
    echo "Copying workspace settings..."
    cp "$WORKSPACE_DIR/.vscode/settings.json" /tmp/coverage_workspace_settings.json 2>&1 || echo "{}" > /tmp/coverage_workspace_settings.json
else
    echo "{}" > /tmp/coverage_workspace_settings.json
fi

# Copy user settings
if [ -f "/home/ga/.config/Code/User/settings.json" ]; then
    echo "Copying user settings..."
    cp "/home/ga/.config/Code/User/settings.json" /tmp/coverage_user_settings.json 2>&1 || echo "{}" > /tmp/coverage_user_settings.json
else
    echo "{}" > /tmp/coverage_user_settings.json
fi

# List all files in workspace for debugging
ls -la "$WORKSPACE_DIR" > /tmp/coverage_workspace_files.txt 2>&1

echo "✅ Coverage visualization data exported to /tmp"
echo "Extensions list: /tmp/coverage_extensions.txt"
echo "Workspace: $WORKSPACE_DIR"