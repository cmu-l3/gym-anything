#!/system/bin/sh
# export_result.sh for check_acid_reducer_with_erlotinib@1

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/sdcard/erlotinib_omeprazole_result.txt"

# Take final screenshot
screencap -p /sdcard/task_final.png

# Check output file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    
    # Check modification time
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content (safely encoded)
    # We replace newlines with literal \n for JSON safety in this simple script
    FILE_CONTENT=$(cat "$OUTPUT_PATH" | tr '\n' '|')
fi

# Check if app is in foreground (simple check)
APP_VISIBLE="false"
if dumpsys window | grep mCurrentFocus | grep -q "com.liverpooluni.ichartoncology"; then
    APP_VISIBLE="true"
fi

# Create JSON result
# Using a temporary file approach isn't strictly necessary on /sdcard but good practice
cat > /sdcard/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content_raw": "$FILE_CONTENT",
    "app_visible_at_end": $APP_VISIBLE,
    "screenshot_path": "/sdcard/task_final.png"
}
EOF

echo "Result saved to /sdcard/task_result.json"
echo "=== Export complete ==="