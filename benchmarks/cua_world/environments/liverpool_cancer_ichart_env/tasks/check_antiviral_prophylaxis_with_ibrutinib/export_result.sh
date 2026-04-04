#!/system/bin/sh
echo "=== Exporting task results ==="

# Output paths
RESULT_FILE="/sdcard/interaction_result.txt"
EXPORT_JSON="/sdcard/task_result.json"
START_TIME_FILE="/sdcard/task_start_time.txt"
FINAL_SCREENSHOT="/sdcard/task_final.png"

# Capture final screenshot
screencap -p "$FINAL_SCREENSHOT" 2>/dev/null || true

# Get timestamps
TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check result file
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MOD_TIME="0"
CREATED_DURING_TASK="false"

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    # Read content safely (handle potential binary junk or encoding issues)
    FILE_CONTENT=$(cat "$RESULT_FILE" | head -n 20) 
    FILE_MOD_TIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MOD_TIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# Check if app is in foreground
APP_VISIBLE="false"
if dumpsys window | grep mCurrentFocus | grep -q "com.liverpooluni.ichartoncology"; then
    APP_VISIBLE="true"
fi

# Construct JSON manually (sh on Android often lacks jq)
echo "{" > "$EXPORT_JSON"
echo "  \"task_start\": $TASK_START," >> "$EXPORT_JSON"
echo "  \"task_end\": $TASK_END," >> "$EXPORT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$EXPORT_JSON"
echo "  \"created_during_task\": $CREATED_DURING_TASK," >> "$EXPORT_JSON"
echo "  \"app_visible\": $APP_VISIBLE," >> "$EXPORT_JSON"
# Escape double quotes in content for valid JSON
ESCAPED_CONTENT=$(echo "$FILE_CONTENT" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
echo "  \"file_content\": \"$ESCAPED_CONTENT\"" >> "$EXPORT_JSON"
echo "}" >> "$EXPORT_JSON"

echo "Export complete. JSON saved to $EXPORT_JSON"
cat "$EXPORT_JSON"