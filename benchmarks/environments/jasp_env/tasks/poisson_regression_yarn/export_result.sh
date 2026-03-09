#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Output File
OUTPUT_PATH="/home/ga/Documents/JASP/YarnBreaks_Poisson.jasp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

EXISTS="false"
CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$OUTPUT_PATH" ]; then
    EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME,
    "output_exists": $EXISTS,
    "output_path": "$OUTPUT_PATH",
    "file_created_during_task": $CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with lenient permissions
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json