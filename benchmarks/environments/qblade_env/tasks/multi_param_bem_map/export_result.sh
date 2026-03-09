#!/bin/bash
echo "=== Exporting Multi-Parameter BEM Map Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define paths
OUTPUT_PATH="/home/ga/Documents/projects/performance_map.wpa"
SCREENSHOT_PATH="/tmp/task_final.png"

# 1. Take final screenshot
DISPLAY=:1 scrot "$SCREENSHOT_PATH" 2>/dev/null || \
    DISPLAY=:1 import -window root "$SCREENSHOT_PATH" 2>/dev/null || true

# 2. Analyze Output File
FILE_EXISTS="false"
FILE_SIZE_BYTES=0
FILE_MODIFIED_DURING_TASK="false"
IS_SAMPLE_COPY="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi

    # Check if it's just a direct copy of a sample file without changes
    # (A real simulation adds significant data, changing the hash and size)
    FILE_HASH=$(md5sum "$OUTPUT_PATH" | awk '{print $1}')
    for sample in /home/ga/Documents/sample_projects/*.wpa; do
        if [ -f "$sample" ]; then
            SAMPLE_HASH=$(md5sum "$sample" 2>/dev/null | awk '{print $1}')
            if [ "$FILE_HASH" == "$SAMPLE_HASH" ]; then
                IS_SAMPLE_COPY="true"
                break
            fi
        fi
    done
fi

# 3. Check App State
APP_RUNNING=$(pgrep -f "[Qq][Bb]lade" > /dev/null && echo "true" || echo "false")

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_file_exists": $FILE_EXISTS,
    "output_file_size_bytes": $FILE_SIZE_BYTES,
    "created_during_task": $FILE_MODIFIED_DURING_TASK,
    "is_sample_copy": $IS_SAMPLE_COPY,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "$SCREENSHOT_PATH"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="