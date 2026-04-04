#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting JSON Validation Result ==="

WORKSPACE_DIR="/home/ga/workspace/json_validation_task"
REPORT_FILE="$WORKSPACE_DIR/validation_report.md"

# Focus VSCode and trigger save
focus_vscode_window
sleep 1

# Try to save any open files
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Could not trigger save; continuing"
}

# Wait for report file to be created
if [ -f "$REPORT_FILE" ]; then
    echo "✅ Found validation report"
else
    echo "⚠️ Validation report not found at $REPORT_FILE"
fi

# Copy JSON files to /tmp for verifier reference
echo "Copying JSON files for verification..."
cp "$WORKSPACE_DIR/config.json" /tmp/config.json 2>/dev/null || echo "{}" > /tmp/config.json
cp "$WORKSPACE_DIR/database.json" /tmp/database.json 2>/dev/null || echo "{}" > /tmp/database.json
cp "$WORKSPACE_DIR/api_settings.json" /tmp/api_settings.json 2>/dev/null || echo "{}" > /tmp/api_settings.json

# Copy report to /tmp if it exists
if [ -f "$REPORT_FILE" ]; then
    cp "$REPORT_FILE" /tmp/validation_report.md
    echo "✅ Report copied to /tmp for verification"
else
    echo "" > /tmp/validation_report.md
fi

echo "✅ Export complete"
echo "Report location: $REPORT_FILE"