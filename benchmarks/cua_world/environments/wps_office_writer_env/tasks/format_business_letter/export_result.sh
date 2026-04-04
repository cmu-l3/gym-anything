#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Business Letter Formatting Result ==="

# Focus WPS window
wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Take a final screenshot before closing
take_screenshot /tmp/final_letter_screenshot.png

# Check if document exists
DOC_PATH="/home/ga/Documents/draft_letter.docx"
DOC_EXISTS="false"
DOC_SIZE="0"

if [ -f "$DOC_PATH" ]; then
    DOC_EXISTS="true"
    DOC_SIZE=$(stat -c %s "$DOC_PATH" 2>/dev/null || echo "0")
    echo "File exists: $DOC_PATH"
    ls -lh "$DOC_PATH"

    # Copy document to /tmp for verifier access
    cp "$DOC_PATH" /tmp/draft_letter.docx
    chmod 666 /tmp/draft_letter.docx
    echo "Document copied to /tmp/draft_letter.docx"
else
    echo "Warning: File not found on disk"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "document_exists": $DOC_EXISTS,
    "document_path": "$DOC_PATH",
    "document_size": $DOC_SIZE,
    "export_document": "/tmp/draft_letter.docx",
    "screenshot": "/tmp/final_letter_screenshot.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

# Close WPS Writer
echo "Closing WPS Writer..."
# WPS uses Alt+F4 or Ctrl+Q to close
safe_xdotool ga :1 key --delay 200 alt+F4
sleep 2

# Handle "Save changes?" dialog - press "Don't Save" to avoid
# masking agent failure (if they forgot to save)
# In WPS, this is typically handled with Tab + Enter or clicking "Don't Save"
safe_xdotool ga :1 key --delay 100 Tab
sleep 0.3
safe_xdotool ga :1 key --delay 100 Return
sleep 0.5

# If WPS is still running, try Ctrl+Q
if pgrep -f "wps" > /dev/null; then
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 1
fi

echo "=== Export Complete ==="
