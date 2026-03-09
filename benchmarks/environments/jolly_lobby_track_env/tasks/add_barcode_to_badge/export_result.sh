#!/bin/bash
echo "=== Exporting Add Barcode to Badge Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Task End State
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check for Modified Badge Template Files
# Lobby Track stores templates in ProgramData or Public Documents usually.
# We search the entire Wine C: drive for files modified after task start
# that look like Jolly/Lobby Track data.
echo "Searching for modified template files..."

WINE_PREFIX="/home/ga/.wine/drive_c"
MODIFIED_FILE=""
FILE_CONTENT_MATCH="false"
KEYWORDS_FOUND=""

# Find files modified > TASK_START inside Jolly Technologies folders
# Excluding logs, temp files, and the database itself usually (unless template is in DB)
# Common extensions for Jolly templates: .btf, .xml, .bgd
FOUND_FILES=$(find "$WINE_PREFIX" -type f -newermt "@$TASK_START" \
    \( -path "*Jolly Technologies*" -o -path "*Lobby Track*" \) \
    -not -path "*Logs*" -not -path "*Temp*" -not -name "*.log" -not -name "*.txt" \
    2>/dev/null)

if [ -n "$FOUND_FILES" ]; then
    echo "Found modified files:"
    echo "$FOUND_FILES"
    
    # Pick the most likely candidate (largest or specific extension)
    MODIFIED_FILE=$(echo "$FOUND_FILES" | head -1)
    
    # Check content for keywords (binary safe grep)
    if grep -iaqE "Barcode|Symbology|Code39|Code128|QRCode|PDF417" "$MODIFIED_FILE"; then
        FILE_CONTENT_MATCH="true"
        KEYWORDS_FOUND="barcode"
    fi
    
    if grep -iaqE "VisitorID|Visitor ID|SystemID|CardNumber" "$MODIFIED_FILE"; then
        KEYWORDS_FOUND="${KEYWORDS_FOUND},data_binding"
    fi
else
    echo "No relevant modified files found."
fi

# 3. Check if App is Still Running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null || pgrep -f "Lobby" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "template_file_found": $([ -n "$MODIFIED_FILE" ] && echo "true" || echo "false"),
    "template_file_path": "$MODIFIED_FILE",
    "barcode_keyword_in_file": $FILE_CONTENT_MATCH,
    "keywords_found": "$KEYWORDS_FOUND",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="