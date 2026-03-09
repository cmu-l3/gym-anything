#!/bin/bash
echo "=== Exporting Mann-Whitney U Results ==="

# 1. Define Paths
OUTPUT_PATH="/home/ga/Documents/Jamovi/InsectSprays_MannWhitney.omv"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

# 2. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Check File Status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Check App Status
APP_RUNNING="false"
if pgrep -f "jamovi" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON Result
# We will output this to a temp file that the verifier will pull
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $NOW,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "output_path": "$OUTPUT_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json