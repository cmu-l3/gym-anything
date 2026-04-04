#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Consolidate TODO Markers Result ==="

WORKSPACE_DIR="/home/ga/workspace/web_scraper"
OUTPUT_FILE="$WORKSPACE_DIR/TECHNICAL_DEBT.md"

# Focus VSCode and save all files
focus_vscode_window
sleep 0.5

# Save all files
echo "Saving all files..."
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to send save command; continuing"
}

# Wait for TECHNICAL_DEBT.md to be written
if [ -f "$OUTPUT_FILE" ]; then
    echo "Waiting for TECHNICAL_DEBT.md to be fully written..."
    wait_for_file "$OUTPUT_FILE" 5
    echo "✅ TECHNICAL_DEBT.md found"
else
    echo "⚠️ TECHNICAL_DEBT.md not found at $OUTPUT_FILE"
fi

# Give filesystem time to sync
sleep 2

echo "✅ Export complete"
echo "Expected output: $OUTPUT_FILE"

# Debug: show if file exists and size
if [ -f "$OUTPUT_FILE" ]; then
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "unknown")
    echo "File size: $FILE_SIZE bytes"
    echo "First 200 characters:"
    head -c 200 "$OUTPUT_FILE" || echo "(could not read file)"
else
    echo "File does not exist yet"
fi