#!/system/bin/sh
echo "=== Exporting check_anti_tb_interaction_with_sunitinib results ==="

RESULT_FILE="/sdcard/Download/interaction_result.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
EXPORT_JSON="/sdcard/task_result.json"

# 1. Capture timestamps
TASK_END=$(date +%s)
TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")

# 2. Check result file existence and content
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$RESULT_FILE")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if app is in foreground at end of task (optional, but good signal)
# Note: Grepping dumpsys window for mCurrentFocus
APP_VISIBLE="false"
if dumpsys window | grep -i "mCurrentFocus" | grep -q "com.liverpooluni.ichartoncology"; then
    APP_VISIBLE="true"
fi

# 4. Take final screenshot
screencap -p /sdcard/task_final.png

# 5. Construct JSON result
# We construct the JSON manually using echo since jq might not be available on minimal Android
echo "{" > "$EXPORT_JSON"
echo "  \"task_start\": $TASK_START," >> "$EXPORT_JSON"
echo "  \"task_end\": $TASK_END," >> "$EXPORT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$EXPORT_JSON"
echo "  \"file_content\": \"$(echo $FILE_CONTENT | sed 's/"/\\"/g' | tr -d '\n')\"," >> "$EXPORT_JSON"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$EXPORT_JSON"
echo "  \"app_visible_at_end\": $APP_VISIBLE" >> "$EXPORT_JSON"
echo "}" >> "$EXPORT_JSON"

echo "Export complete. JSON saved to $EXPORT_JSON"
cat "$EXPORT_JSON"