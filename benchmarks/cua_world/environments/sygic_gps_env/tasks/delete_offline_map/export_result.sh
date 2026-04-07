#!/system/bin/sh
# Export script for delete_offline_map task
# Runs on Android device

echo "=== Exporting results for delete_offline_map ==="

PACKAGE="com.sygic.aura"
RESULT_JSON="/sdcard/task_result.json"

# 1. Take Final Screenshot
screencap -p /sdcard/task_final.png
echo "Final screenshot saved to /sdcard/task_final.png"

# 2. Check if Map Files Still Exist
CURRENT_MAP_FILES=$(find /sdcard/Android/data/$PACKAGE/ /data/data/$PACKAGE/ -type f -name "*samoa*" -o -name "*as.map*" 2>/dev/null)
if [ -z "$CURRENT_MAP_FILES" ]; then
    MAP_EXISTS="false"
    CURRENT_COUNT="0"
else
    MAP_EXISTS="true"
    CURRENT_COUNT=$(echo "$CURRENT_MAP_FILES" | wc -l)
fi

# 3. Check Initial State for Comparison
INITIAL_COUNT=$(cat /sdcard/initial_map_count.txt 2>/dev/null || echo "0")

# 4. Check Storage Delta
INITIAL_STORAGE=$(cat /sdcard/initial_storage_size.txt 2>/dev/null || echo "0")
CURRENT_STORAGE=$(du -s /data/data/$PACKAGE/ 2>/dev/null | awk '{print $1}' || echo "0")

# 5. Check if App is Running (Agent shouldn't have killed it)
if pidof "$PACKAGE" > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 6. Construct JSON
# Note: creating JSON in shell is tricky, keeping it simple
echo "{" > "$RESULT_JSON"
echo "  \"map_files_exist\": $MAP_EXISTS," >> "$RESULT_JSON"
echo "  \"initial_file_count\": $INITIAL_COUNT," >> "$RESULT_JSON"
echo "  \"final_file_count\": $CURRENT_COUNT," >> "$RESULT_JSON"
echo "  \"initial_storage_kb\": $INITIAL_STORAGE," >> "$RESULT_JSON"
echo "  \"final_storage_kb\": $CURRENT_STORAGE," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result JSON created at $RESULT_JSON:"
cat "$RESULT_JSON"

echo "=== Export Complete ==="