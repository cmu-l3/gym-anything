#!/system/bin/sh
# Export script for evaluate_relay_site task on Android

echo "=== Exporting evaluate_relay_site results ==="

PACKAGE="ch.opengis.qfield"
GPKG_PATH="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
RESULT_JSON="/sdcard/task_result.json"

# 1. Capture Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check File Stats (Anti-gaming: modification time)
FILE_MODIFIED="false"
if [ -f "$GPKG_PATH" ]; then
    # Android stat might be limited, trying basic approach
    # In full linux: stat -c %Y file. In android toybox: stat -c %Y might work
    GPKG_MTIME=$(stat -c %Y "$GPKG_PATH" 2>/dev/null || echo "0")
    GPKG_SIZE=$(stat -c %s "$GPKG_PATH" 2>/dev/null || echo "0")
    
    if [ "$GPKG_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
else
    GPKG_MTIME="0"
    GPKG_SIZE="0"
fi

# 3. Check App State
APP_RUNNING=$(pidof ch.opengis.qfield > /dev/null && echo "true" || echo "false")

# 4. Take Final Screenshot
echo "Capturing final screenshot..."
screencap -p /sdcard/task_final.png

# 5. Create Result JSON
# Note: Android shell usually doesn't have jq, so we write JSON manually
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"task_end\": $TASK_END," >> "$RESULT_JSON"
echo "  \"gpkg_path\": \"$GPKG_PATH\"," >> "$RESULT_JSON"
echo "  \"gpkg_mtime\": $GPKG_MTIME," >> "$RESULT_JSON"
echo "  \"gpkg_size\": $GPKG_SIZE," >> "$RESULT_JSON"
echo "  \"file_modified\": $FILE_MODIFIED," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "=== Export Complete ==="
cat "$RESULT_JSON"