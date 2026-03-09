#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Data Table Result ==="

# Focus WPS window
wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Take a final screenshot
take_screenshot /tmp/final_table_screenshot.png

# Check for the saved file in common locations
SAVED_FILE=""
for location in \
    "/home/ga/Documents/amazon_q4_report.docx" \
    "/home/ga/amazon_q4_report.docx" \
    "/home/ga/Desktop/amazon_q4_report.docx" \
    "/tmp/amazon_q4_report.docx" \
    "/home/ga/Documents/sales_report.docx" \
    "/home/ga/sales_report.docx"; do
    if [ -f "$location" ]; then
        SAVED_FILE="$location"
        echo "Found saved file at: $SAVED_FILE"
        break
    fi
done

# REMOVED: Wildcard fallback for any .docx file
# The previous code found ANY .docx file modified in last 10 minutes, which could
# incorrectly accept pre-existing documents instead of the agent's work.
# The agent MUST save to one of the expected locations with the expected filename.
if [ -z "$SAVED_FILE" ]; then
    echo "Warning: Document not found at any expected location."
    echo "Expected filenames: amazon_q4_report.docx or sales_report.docx"
    echo "Expected locations: /home/ga/Documents/, /home/ga/, /tmp/"
fi

DOC_EXISTS="false"
DOC_SIZE="0"
DOC_PATH=""

if [ -n "$SAVED_FILE" ]; then
    DOC_EXISTS="true"
    DOC_SIZE=$(stat -c %s "$SAVED_FILE" 2>/dev/null || echo "0")
    DOC_PATH="$SAVED_FILE"

    # Copy to standard location for verifier
    cp "$SAVED_FILE" /home/ga/Documents/amazon_q4_report.docx 2>/dev/null || true
    cp "$SAVED_FILE" /tmp/amazon_q4_report.docx
    chmod 666 /tmp/amazon_q4_report.docx
    ls -lh "$SAVED_FILE"
    echo "Document copied to /tmp/amazon_q4_report.docx"
else
    echo "Warning: amazon_q4_report.docx not found"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "document_exists": $DOC_EXISTS,
    "document_path": "$DOC_PATH",
    "document_size": $DOC_SIZE,
    "export_document": "/tmp/amazon_q4_report.docx",
    "screenshot": "/tmp/final_table_screenshot.png",
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
safe_xdotool ga :1 key --delay 200 alt+F4
sleep 2

# Handle "Save changes?" dialog - don't save to avoid masking failures
safe_xdotool ga :1 key --delay 100 Tab
sleep 0.3
safe_xdotool ga :1 key --delay 100 Return
sleep 0.5

# If WPS is still running, force quit
if pgrep -f "wps" > /dev/null; then
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 1
fi

echo "=== Export Complete ==="
