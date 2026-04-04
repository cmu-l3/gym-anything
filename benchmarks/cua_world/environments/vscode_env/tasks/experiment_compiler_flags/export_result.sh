#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Experiment Compiler Flags Result ==="

WORKSPACE_DIR="/home/ga/workspace/performance_test"
TASKS_JSON="$WORKSPACE_DIR/.vscode/tasks.json"

# Save VSCode if open
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to save in VSCode; continuing"
}

# Export tasks.json to /tmp if it exists
if [ -f "$TASKS_JSON" ]; then
    echo "✅ Found tasks.json, copying to /tmp"
    cp "$TASKS_JSON" /tmp/tasks.json
    chmod 644 /tmp/tasks.json
    
    # Show content for debugging
    echo "=== tasks.json content ==="
    cat "$TASKS_JSON"
    echo "========================="
else
    echo "⚠️ tasks.json not found at $TASKS_JSON"
    echo "{}" > /tmp/tasks.json
fi

# Check if any binaries were built (optional)
echo "Checking for compiled binaries..."
ls -lh "$WORKSPACE_DIR"/benchmark* 2>/dev/null || echo "No binaries found (this is okay)"

# Export directory listing
ls -la "$WORKSPACE_DIR/.vscode/" > /tmp/vscode_dir_listing.txt 2>&1 || echo "No .vscode directory" > /tmp/vscode_dir_listing.txt

echo "✅ Export complete"
echo "Tasks file: $TASKS_JSON"