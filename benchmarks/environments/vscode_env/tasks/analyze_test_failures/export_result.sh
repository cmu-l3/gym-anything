#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Analyze Test Failures Result ==="

WORKSPACE_DIR="/home/ga/workspace"
SUMMARY_FILE="$WORKSPACE_DIR/test_failures_summary.txt"

# Try to save any open files in VSCode
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to save via keyboard shortcut; continuing"
}

# Wait a moment for file to be written
sleep 2

# Check if summary file exists
if [ -f "$SUMMARY_FILE" ]; then
    echo "Summary file found, exporting..."
    cp "$SUMMARY_FILE" /tmp/test_failures_summary.txt
    echo "Lines in summary: $(wc -l < "$SUMMARY_FILE")"
    echo "✅ Summary exported to /tmp/test_failures_summary.txt"
else
    echo "⚠️ Summary file not found at $SUMMARY_FILE"
    touch /tmp/test_failures_summary.txt
fi

echo "✅ Export complete"