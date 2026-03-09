#!/bin/bash
set -e
echo "=== Exporting keyboard_shortcuts_tile_view results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Output File Stats
OUTPUT_PATH="/home/ga/shortcuts_reference.txt"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
LINE_COUNT=0
FILE_SIZE=0

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if modified after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Count non-empty lines
    LINE_COUNT=$(grep -cve '^\s*$' "$OUTPUT_PATH" 2>/dev/null || echo "0")
fi

# 2. Take Final Screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS=$([ -f /tmp/task_final.png ] && echo "true" || echo "false")

# 3. Create JSON Result
# We will rely on the verifier to pull the actual text file content, 
# but we provide metadata here.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_line_count": $LINE_COUNT,
    "file_size_bytes": $FILE_SIZE,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "output_file_path": "$OUTPUT_PATH"
}
EOF

# Move JSON to accessible location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json