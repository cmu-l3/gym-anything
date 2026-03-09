#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Business Letter Result ==="

# Focus Writer window if it exists
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Do NOT force-save - the agent is responsible for saving
# Task specifies ODT format only - do not accept other formats
OUTPUT_FILE="/home/ga/Documents/partnership_letter.odt"

# Check ONLY for the specified ODT format
# The task explicitly requires saving as ODF Text Document (.odt)
FILE_FOUND="false"
ACTUAL_FILE=""
FILE_SIZE_BYTES=0
WRONG_FORMAT_FOUND="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_FOUND="true"
    ACTUAL_FILE="$OUTPUT_FILE"
    FILE_SIZE_BYTES=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    echo "File exists: $OUTPUT_FILE (${FILE_SIZE_BYTES} bytes)"
else
    echo "Warning: Expected ODT file not found at $OUTPUT_FILE"
    # Check if agent saved in wrong format (for diagnostic purposes only)
    if [ -f "/home/ga/Documents/partnership_letter.doc" ]; then
        WRONG_FORMAT_FOUND="true"
        echo "ERROR: File saved as .doc instead of required .odt format"
    elif [ -f "/home/ga/Documents/partnership_letter.docx" ]; then
        WRONG_FORMAT_FOUND="true"
        echo "ERROR: File saved as .docx instead of required .odt format"
    fi
    ls -la /home/ga/Documents/ 2>/dev/null || true
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Close Writer (Ctrl+Q)
echo "Closing Apache OpenOffice Writer..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

# Handle "Save changes?" dialog - press "Don't Save" to avoid
# masking agent failure (if they forgot to save, don't save for them)
# OpenOffice uses Alt+D for "Don't Save" or Tab to navigate
safe_xdotool ga :1 key --delay 100 alt+d
sleep 0.5
# Also try pressing N for No or clicking the appropriate button
safe_xdotool ga :1 key --delay 100 n
sleep 0.3

# Extract document content if file exists (for verification)
DOC_CONTENT=""
if [ "$FILE_FOUND" = "true" ] && [ -n "$ACTUAL_FILE" ]; then
    # ODT is a ZIP file with content.xml
    DOC_CONTENT=$(unzip -p "$ACTUAL_FILE" content.xml 2>/dev/null | sed 's/<[^>]*>//g' | tr -s ' \n' ' ' | head -c 2000)
fi

# Escape special characters in content for JSON
DOC_CONTENT_ESCAPED=$(echo "$DOC_CONTENT" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' ' ')

# Create JSON result in temp file first
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_FILE",
    "file_size_bytes": $FILE_SIZE_BYTES,
    "document_content_preview": "$DOC_CONTENT_ESCAPED",
    "wrong_format_found": $WRONG_FORMAT_FOUND,
    "expected_format": ".odt (ODF Text Document)",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="
