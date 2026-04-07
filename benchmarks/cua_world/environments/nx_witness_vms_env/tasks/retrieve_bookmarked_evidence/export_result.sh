#!/bin/bash
echo "=== Exporting retrieve_bookmarked_evidence results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_PATH="/home/ga/Documents/evidence_export.mkv"

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check File Existence & Stats
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_DURATION="0"
FILE_FORMAT=""
CREATED_DURING_TASK="false"

if [ -f "$TARGET_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_PATH")
    FILE_MTIME=$(stat -c %Y "$TARGET_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
    
    # 3. Analyze Video with ffprobe
    # Get duration in seconds
    FILE_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$TARGET_PATH" 2>/dev/null || echo "0")
    
    # Get format/codec info
    FILE_FORMAT=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$TARGET_PATH" 2>/dev/null || echo "unknown")
fi

# 4. Gather Bookmark Metadata for Verification
BOOKMARK_DURATION_MS=$(cat /tmp/target_bookmark_duration_ms.txt 2>/dev/null || echo "10000")
EXPECTED_DURATION_SEC=$(python3 -c "print(($BOOKMARK_DURATION_MS / 1000.0) + 20.0)" 2>/dev/null || echo "30.0")

# 5. Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_path": "$TARGET_PATH",
    "file_size": $FILE_SIZE,
    "file_duration_sec": "$FILE_DURATION",
    "file_format": "$FILE_FORMAT",
    "created_during_task": $CREATED_DURING_TASK,
    "expected_duration_sec": $EXPECTED_DURATION_SEC,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON:"
cat /tmp/task_result.json

echo "=== Export Complete ==="