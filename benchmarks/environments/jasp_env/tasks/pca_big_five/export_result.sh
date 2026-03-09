#!/bin/bash
echo "=== Exporting PCA Big Five results ==="

# 1. Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather task metrics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_PATH="/home/ga/Documents/JASP/BigFive_PCA.jasp"

OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    # Verify file was modified AFTER task started
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Create JSON result
# We use a temp file and move it to avoid permission issues if the agent user owns the dir
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_path": "$OUTPUT_PATH",
    "output_exists": $OUTPUT_EXISTS,
    "output_size": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json