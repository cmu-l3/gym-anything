#!/bin/bash
echo "=== Exporting Custom Screen Definition Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/custom_screen_definition_start_ts 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/screen_report.json"

FILE_EXISTS=false
FILE_IS_NEW=false
FILE_MTIME=0

if [ -f "$OUTPUT" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$OUTPUT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW=true
    fi
fi

SCREEN_FILE_EXISTS=false
SCREEN_FILE_IS_NEW=false
SCREEN_FILE_MTIME=0
SCREEN_FILE_CONTENT=""

# Search for the screen file (typically in plugins)
FOUND_SCREEN=$(find /home/ga/cosmos/plugins -type f -iname "*thermal_overview*.txt" 2>/dev/null | grep -i "screens" | head -1)

if [ -n "$FOUND_SCREEN" ]; then
    SCREEN_FILE_EXISTS=true
    SCREEN_FILE_MTIME=$(stat -c %Y "$FOUND_SCREEN" 2>/dev/null || echo "0")
    if [ "$SCREEN_FILE_MTIME" -ge "$TASK_START" ]; then
        SCREEN_FILE_IS_NEW=true
    fi
    SCREEN_FILE_CONTENT=$(cat "$FOUND_SCREEN" | base64 -w 0)
fi

# Take final screenshot
DISPLAY=:1 import -window root /tmp/custom_screen_definition_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/custom_screen_definition_end.png 2>/dev/null || true

cat > /tmp/custom_screen_definition_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "screen_file_exists": $SCREEN_FILE_EXISTS,
    "screen_file_is_new": $SCREEN_FILE_IS_NEW,
    "screen_file_mtime": $SCREEN_FILE_MTIME,
    "screen_file_content_b64": "$SCREEN_FILE_CONTENT"
}
EOF

echo "File exists: $FILE_EXISTS"
echo "Screen file exists: $SCREEN_FILE_EXISTS"
echo "=== Export Complete ==="