#!/bin/bash
# set -euo pipefail

echo "=== Exporting Integrate Custom Build Tool Result ==="

WORKSPACE_DIR="/home/ga/workspace/fastbuild_project"
TASKS_JSON_PATH="$WORKSPACE_DIR/.vscode/tasks.json"

# Export tasks.json to /tmp for verification
if [ -f "$TASKS_JSON_PATH" ]; then
    echo "Copying tasks.json to /tmp..."
    cp "$TASKS_JSON_PATH" /tmp/tasks.json
    echo "✅ tasks.json exported"
    
    # Show content for debugging
    echo ""
    echo "tasks.json content:"
    cat "$TASKS_JSON_PATH"
    echo ""
else
    echo "⚠️ tasks.json not found at $TASKS_JSON_PATH"
    echo "{}" > /tmp/tasks.json
fi

# Export workspace structure for debugging
echo "Workspace structure:" > /tmp/workspace_info.txt
ls -la "$WORKSPACE_DIR/" >> /tmp/workspace_info.txt 2>&1
ls -la "$WORKSPACE_DIR/.vscode/" >> /tmp/workspace_info.txt 2>&1

echo "✅ Export complete"
echo "Tasks file: $TASKS_JSON_PATH"