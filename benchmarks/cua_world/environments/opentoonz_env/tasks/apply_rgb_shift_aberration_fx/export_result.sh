#!/bin/bash
echo "=== Exporting task results ==="

# 1. Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/OpenToonz/output/aberration"

# 2. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Analyze Output Files
# Find PNG files in the output directory
# Sort by name to find a sequence
OUTPUT_FILES=$(find "$OUTPUT_DIR" -name "*.png" | sort)
FILE_COUNT=$(echo "$OUTPUT_FILES" | grep -v "^$" | wc -l)
FIRST_FILE=$(echo "$OUTPUT_FILES" | head -n 1)

OUTPUT_EXISTS="false"
FILES_NEWER="false"
SAMPLE_FILE_PATH=""
SAMPLE_FILE_SIZE=0

if [ "$FILE_COUNT" -gt 0 ]; then
    OUTPUT_EXISTS="true"
    SAMPLE_FILE_PATH="$FIRST_FILE"
    
    # Check timestamps of the first file
    FILE_MTIME=$(stat -c %Y "$FIRST_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILES_NEWER="true"
    fi
    
    SAMPLE_FILE_SIZE=$(stat -c %s "$FIRST_FILE" 2>/dev/null || echo "0")
fi

# 4. Check if App is Running
APP_RUNNING="false"
if pgrep -f "opentoonz" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_dir": "$OUTPUT_DIR",
    "output_exists": $OUTPUT_EXISTS,
    "file_count": $FILE_COUNT,
    "files_created_during_task": $FILES_NEWER,
    "sample_file_path": "$SAMPLE_FILE_PATH",
    "sample_file_size": $SAMPLE_FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save JSON
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="