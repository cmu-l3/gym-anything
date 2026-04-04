#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Team Snippets Result ==="

SNIPPET_FILE="/home/ga/.config/Code/User/snippets/python.json"

# Try to save any open files in VSCode
echo "Attempting to save open files..."
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Could not send save command; continuing"
}

# Give time for file operations to complete
sleep 2

# Export the snippet file to /tmp for verification
if [ -f "$SNIPPET_FILE" ]; then
    echo "✅ Snippet file found at $SNIPPET_FILE"
    cp "$SNIPPET_FILE" /tmp/python.json 2>&1 || echo "Failed to copy snippet file"
    
    echo "Snippet file contents:"
    echo "---"
    cat "$SNIPPET_FILE" 2>&1 || echo "Could not read snippet file"
    echo "---"
else
    echo "⚠️ Snippet file not found at $SNIPPET_FILE"
    echo "Creating empty placeholder for verifier"
    echo "{}" > /tmp/python.json
fi

# Also check if file was created in any alternate location
echo ""
echo "Checking for snippet files in Code directory..."
find /home/ga/.config/Code/User/snippets/ -name "*.json" -type f 2>/dev/null | while read file; do
    echo "Found: $file"
done

# Export workspace files (optional, for debugging)
if [ -d "/home/ga/workspace/api_service" ]; then
    cp -r /home/ga/workspace/api_service /tmp/workspace_backup 2>/dev/null || true
fi

echo ""
echo "✅ Export complete"
echo "Snippet file location: $SNIPPET_FILE"
echo "Exported to: /tmp/python.json"