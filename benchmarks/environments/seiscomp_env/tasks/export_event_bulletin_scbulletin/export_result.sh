#!/bin/bash
echo "=== Exporting export_event_bulletin_scbulletin result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
TASK="export_event_bulletin_scbulletin"
OUTPUT_FILE="/home/ga/Desktop/noto_bulletin.txt"

TASK_START=$(cat /tmp/${TASK}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK}_end_screenshot.png 2>/dev/null || true

# Check file existence and freshness
FILE_EXISTS=false
FILE_IS_NEW=false
FILE_SIZE=0
HAS_CONTENT=false
HAS_EVENT_DATA=false
HAS_ORIGIN_LINE=false
HAS_MAGNITUDE=false
EVENT_COUNT_IN_FILE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")

    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW=true
    fi

    if [ "$FILE_SIZE" -gt "50" ]; then
        HAS_CONTENT=true
    fi

    # Check for common bulletin content patterns
    # scbulletin default output contains origin information
    if grep -qiE "^[0-9]{4}|origin|event|earthquake|Noto|latitude|longitude|magnitude|ML|Mw|mb|Ms" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_EVENT_DATA=true
    fi

    # Check for coordinate-like lines (origin lines in scbulletin output often contain
    # lat/lon/depth values)
    if grep -qE "[0-9]+\.[0-9]+.*[0-9]+\.[0-9]+.*[0-9]+" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_ORIGIN_LINE=true
    fi

    # Check for magnitude values (M followed by number)
    if grep -qiE "(M[wlbcs]?[ ]?[0-9]+\.[0-9]+)|([Mm]ag.*[0-9]+\.[0-9]+)|(Noto)" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_MAGNITUDE=true
    fi

    # Count events (lines starting with year-month-day pattern are event headers)
    EVENT_COUNT_IN_FILE=$(grep -cE "^20[0-9]{2}-[0-9]{2}-[0-9]{2}" "$OUTPUT_FILE" 2>/dev/null || echo "0")
    echo "Event lines in file: $EVENT_COUNT_IN_FILE"

    echo "File size: $FILE_SIZE bytes"
    echo "File mtime: $FILE_MTIME (task start: $TASK_START)"
    echo "First 20 lines of bulletin:"
    head -20 "$OUTPUT_FILE" 2>/dev/null || true
fi

# Copy bulletin file to /tmp for verifier to read
if [ -f "$OUTPUT_FILE" ]; then
    cp "$OUTPUT_FILE" /tmp/${TASK}_bulletin_copy.txt 2>/dev/null || true
fi

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "Has content: $HAS_CONTENT"
echo "Has event data: $HAS_EVENT_DATA"
echo "Has origin line: $HAS_ORIGIN_LINE"
echo "Has magnitude: $HAS_MAGNITUDE"

cat > /tmp/${TASK}_result.json << EOF
{
    "task": "$TASK",
    "task_start": $TASK_START,
    "output_file": "$OUTPUT_FILE",
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_size": $FILE_SIZE,
    "has_content": $HAS_CONTENT,
    "has_event_data": $HAS_EVENT_DATA,
    "has_origin_line": $HAS_ORIGIN_LINE,
    "has_magnitude": $HAS_MAGNITUDE,
    "event_count_in_file": ${EVENT_COUNT_IN_FILE:-0}
}
EOF

echo "Result written to /tmp/${TASK}_result.json"
cat /tmp/${TASK}_result.json
echo "=== Export complete ==="
