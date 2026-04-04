#!/system/bin/sh
echo "=== Exporting test_offline_mode_handling results ==="

# 1. Capture final state screenshot
screencap -p /sdcard/task_final.png

# 2. Check Wi-Fi Status (Critical Check)
# svc wifi does not output status easily, use dumpsys or settings
WIFI_STATUS_VAL=$(settings get global wifi_on)
# Usually 1=on, 0=off. verifying via ping is more robust for "connectivity"
NETWORK_ONLINE="false"
if ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; then
    NETWORK_ONLINE="true"
fi

# 3. Check Report File
REPORT_PATH="/sdcard/offline_test_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    # Read content (safely, first 500 chars)
    REPORT_CONTENT=$(head -c 500 "$REPORT_PATH")
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Create JSON Result
# We construct JSON manually using echo since jq might not be available on all Android subsets
JSON_PATH="/sdcard/task_result.json"
echo "{" > "$JSON_PATH"
echo "  \"wifi_enabled_setting\": \"$WIFI_STATUS_VAL\"," >> "$JSON_PATH"
echo "  \"network_online\": $NETWORK_ONLINE," >> "$JSON_PATH"
echo "  \"report_exists\": $REPORT_EXISTS," >> "$JSON_PATH"
echo "  \"report_size\": $REPORT_SIZE," >> "$JSON_PATH"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$JSON_PATH"
echo "  \"report_content_preview\": \"$REPORT_CONTENT\"" >> "$JSON_PATH"
echo "}" >> "$JSON_PATH"

echo "Export complete. Result saved to $JSON_PATH"
cat "$JSON_PATH"