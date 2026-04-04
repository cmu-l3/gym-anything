#!/system/bin/sh
echo "=== Exporting results for select_safer_aldosterone_antagonist_abiraterone ==="

TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/sdcard/safety_check.json"

# Capture final screenshot
screencap -p /sdcard/task_final.png

# Check output file status
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT="{}"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    # Android `stat` might be limited, using simplified check
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
fi

# App running status
APP_RUNNING=$(pidof com.liverpooluni.ichartoncology > /dev/null && echo "true" || echo "false")

# Create result JSON
# Note: creating strictly valid JSON string in shell is tricky, keeping it simple
cat > /sdcard/task_result.json <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "file_exists": $FILE_EXISTS,
  "file_created_during_task": $FILE_CREATED_DURING_TASK,
  "app_running": $APP_RUNNING,
  "output_content": $FILE_CONTENT
}
EOF

echo "Result exported to /sdcard/task_result.json"