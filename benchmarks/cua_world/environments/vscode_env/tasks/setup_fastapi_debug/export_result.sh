#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting FastAPI Debug Configuration Result ==="

WORKSPACE_DIR="/home/ga/workspace/fastapi_project"
LAUNCH_JSON="$WORKSPACE_DIR/.vscode/launch.json"

# Try to save any open files in VSCode
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to send save command; continuing"
}

# Wait a moment for file to be written
sleep 2

# Export launch.json to /tmp if it exists
if [ -f "$LAUNCH_JSON" ]; then
    echo "Copying launch.json to /tmp..."
    cp "$LAUNCH_JSON" /tmp/launch.json
    echo "✅ launch.json exported"
    
    # Also export file info for debugging
    ls -lh "$LAUNCH_JSON" > /tmp/launch_json_info.txt
    echo "File size: $(stat -f%z "$LAUNCH_JSON" 2>/dev/null || stat -c%s "$LAUNCH_JSON" 2>/dev/null) bytes" >> /tmp/launch_json_info.txt
else
    echo "⚠️ launch.json not found at $LAUNCH_JSON"
    echo "not_found" > /tmp/launch.json
    ls -la "$WORKSPACE_DIR/.vscode/" > /tmp/launch_json_info.txt 2>&1 || echo "No .vscode directory" > /tmp/launch_json_info.txt
fi

# Export workspace structure for debugging
echo "Exporting workspace structure..."
find "$WORKSPACE_DIR" -type f -name "*.json" > /tmp/json_files.txt 2>&1 || echo "No JSON files found" > /tmp/json_files.txt

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"