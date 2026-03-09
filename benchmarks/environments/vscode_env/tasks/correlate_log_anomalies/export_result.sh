#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Log Correlation Result ==="

WORKSPACE_DIR="/home/ga/workspace/log_analysis"
REPORT_FILE="$WORKSPACE_DIR/docs/incident_report_2024-01-23.md"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to trigger save; continuing"
}

# Wait for report file to exist
wait_for_file "$REPORT_FILE" 3

# Copy report to /tmp for verifier
if [ -f "$REPORT_FILE" ]; then
    cp "$REPORT_FILE" /tmp/incident_report_2024-01-23.md
    echo "✅ Incident report copied to /tmp"
else
    echo "⚠️ Incident report not found at $REPORT_FILE"
    touch /tmp/incident_report_2024-01-23.md
fi

# Also copy any other markdown files in docs as backup
cp "$WORKSPACE_DIR/docs"/*.md /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Expected report location: $REPORT_FILE"