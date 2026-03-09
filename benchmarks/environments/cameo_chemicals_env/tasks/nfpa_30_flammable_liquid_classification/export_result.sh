#!/bin/bash
# export_result.sh - Post-task hook for nfpa_30_flammable_liquid_classification

echo "=== Exporting NFPA 30 Classification Result ==="

# 1. Capture Final State Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
echo "Final screenshot captured."

# 2. Collect Task Timing Data
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Analyze Output File
OUTPUT_PATH="/home/ga/Documents/flammable_liquid_classes.csv"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Anti-gaming: Check if file was modified AFTER task start
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
fi

# 4. Check App State
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 5. Create Result JSON
# Using a temp file to avoid permission issues before copying
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="