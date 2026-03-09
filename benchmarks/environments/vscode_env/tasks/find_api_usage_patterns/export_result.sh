#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Find API Usage Patterns Result ==="

# Try to save any open files in VSCode
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to save files; continuing"
}

# Wait for file to be written if it exists
LEARNINGS_FILE="/home/ga/workspace/api_usage_learnings.md"
if [ -f "$LEARNINGS_FILE" ]; then
    wait_for_file "$LEARNINGS_FILE" 3
fi

# Copy the learnings file to /tmp for verification
if [ -f "$LEARNINGS_FILE" ]; then
    echo "Copying api_usage_learnings.md to /tmp..."
    cp "$LEARNINGS_FILE" /tmp/api_usage_learnings.md
    echo "✅ Summary file exported to /tmp"
    echo "File size: $(wc -c < "$LEARNINGS_FILE") bytes"
    echo "Lines: $(wc -l < "$LEARNINGS_FILE")"
else
    echo "⚠️ Summary file not found at $LEARNINGS_FILE"
    echo "not_created" > /tmp/api_usage_learnings.md
fi

echo "✅ Export complete"