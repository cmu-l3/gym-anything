#!/system/bin/sh
echo "=== Exporting notification channels result ==="

PACKAGE="com.robert.fcView"
OUTPUT_FILE="/sdcard/notification_config.txt"
RESULT_JSON="/sdcard/task_result.json"

# 1. Capture final screenshot
screencap -p /sdcard/task_final.png

# 2. Get task timings
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check Agent's Output File
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_TIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    # Read content, escape newlines for JSON
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
fi

# 4. Get Actual System State (The Ground Truth)
# We use 'cmd notification list_channels' to get the raw source of truth
# Output format is usually:
#   channelId=... name=... importance=...
SYSTEM_STATE_RAW=$(cmd notification list_channels $PACKAGE 1000 2>/dev/null | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

# 5. Get Initial State (for comparison)
INITIAL_STATE_RAW=""
if [ -f "/sdcard/initial_channels.txt" ]; then
    INITIAL_STATE_RAW=$(cat /sdcard/initial_channels.txt | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
fi

# 6. Construct JSON
# We construct it manually because 'jq' might not be available on minimal Android
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"task_end\": $TASK_END," >> "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"file_content\": \"$FILE_CONTENT\"," >> "$RESULT_JSON"
echo "  \"system_state_raw\": \"$SYSTEM_STATE_RAW\"," >> "$RESULT_JSON"
echo "  \"initial_state_raw\": \"$INITIAL_STATE_RAW\"," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="