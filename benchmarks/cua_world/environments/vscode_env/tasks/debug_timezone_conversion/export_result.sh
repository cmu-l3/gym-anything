#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Debug Timezone Conversion Result ==="

WORKSPACE_DIR="/home/ga/workspace/meeting-scheduler"
CONVERTER_FILE="$WORKSPACE_DIR/utils/dateConverter.js"

# Focus VSCode and save file
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to trigger save; continuing"
}

# Wait for file to be written
wait_for_file "$CONVERTER_FILE" 5

# Copy the modified file to /tmp for verification
if [ -f "$CONVERTER_FILE" ]; then
    echo "Copying dateConverter.js to /tmp..."
    cp "$CONVERTER_FILE" /tmp/dateConverter.js
    echo "✅ File exported to /tmp/dateConverter.js"
else
    echo "⚠️ File not found at $CONVERTER_FILE"
    echo "" > /tmp/dateConverter.js
fi

# Export git diff if available
cd "$WORKSPACE_DIR"
if [ -d .git ]; then
    echo "Exporting git diff..."
    sudo -u ga git diff utils/dateConverter.js > /tmp/dateConverter.diff 2>&1 || echo "" > /tmp/dateConverter.diff
    echo "✅ Git diff exported to /tmp/dateConverter.diff"
fi

# Export file stats
if [ -f "$CONVERTER_FILE" ]; then
    stat "$CONVERTER_FILE" > /tmp/dateConverter_stat.txt 2>&1
    wc -l "$CONVERTER_FILE" > /tmp/dateConverter_lines.txt 2>&1
fi

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"
echo "Modified file: $CONVERTER_FILE"