#!/bin/bash
echo "=== Exporting Heckman Task Results ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/gretl_output/heckman_results.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Output File
OUTPUT_EXISTS=false
FILE_CREATED_DURING_TASK=false
OUTPUT_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS=true
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK=true
    fi
fi

# 3. Check if Gretl is still running
APP_RUNNING=false
if pgrep -f "gretl" > /dev/null; then
    APP_RUNNING=true
fi

# 4. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "output_path": "$OUTPUT_FILE"
}
EOF

# 5. Set permissions for the verifier to read
chmod 644 /tmp/task_result.json
chmod 644 /tmp/task_final.png 2>/dev/null || true
if [ -f "$OUTPUT_FILE" ]; then
    chmod 644 "$OUTPUT_FILE"
fi

echo "Export complete. Result:"
cat /tmp/task_result.json