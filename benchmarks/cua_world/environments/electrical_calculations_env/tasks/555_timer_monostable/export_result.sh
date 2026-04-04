#!/system/bin/sh
echo "=== Exporting 555 Timer Monostable results ==="

# 1. Capture final screenshot (CRITICAL for VLM verification)
screencap -p /sdcard/task_final.png

# 2. Gather Task Data
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
RESULT_FILE="/sdcard/tasks/555_timer_monostable/result.txt"

# 3. Check Result File Status
if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    # Read content, stripping whitespace
    FILE_CONTENT=$(cat "$RESULT_FILE" | tr -d '[:space:]')
    
    # Get file modification time
    FILE_MTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    
    # Anti-gaming: Check if file was created AFTER task start
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    FILE_EXISTS="false"
    FILE_CONTENT=""
    FILE_CREATED_DURING_TASK="false"
fi

# 4. Check App Status (is it actually running?)
if pidof com.hsn.electricalcalculations > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 5. Create JSON Result
# We write to /sdcard/task_result.json so the host verifier can copy it easily
cat > /sdcard/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_content": "$FILE_CONTENT",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/sdcard/task_final.png"
}
EOF

echo "Export complete. JSON saved to /sdcard/task_result.json"
cat /sdcard/task_result.json