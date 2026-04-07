#!/system/bin/sh
# Export script for recover_null_island_points task.
# Runs inside the Android environment.

echo "=== Exporting task results ==="

PACKAGE="ch.opengis.qfield"
GPKG_PATH="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
RESULT_JSON="/sdcard/task_result.json"
FINAL_SCREENSHOT="/sdcard/task_final.png"

# 1. Capture Final Screenshot
screencap -p "$FINAL_SCREENSHOT"
echo "Screenshot saved to $FINAL_SCREENSHOT"

# 2. Check timestamps
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
FILE_MOD_TIME=$(stat -c %Y "$GPKG_PATH" 2>/dev/null || echo "0")
WAS_MODIFIED="false"
if [ "$FILE_MOD_TIME" -gt "$TASK_START" ]; then
    WAS_MODIFIED="true"
fi

# 3. Check App State
APP_RUNNING="false"
if pidof "$PACKAGE" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create result JSON for the verifier to consume
# We verify the actual data geometry in the python verifier on the host,
# so we just export metadata here.
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"file_modified\": $WAS_MODIFIED," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"gpkg_path\": \"$GPKG_PATH\"," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"$FINAL_SCREENSHOT\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

chmod 666 "$RESULT_JSON"
chmod 666 "$GPKG_PATH"

echo "Export complete. Result at $RESULT_JSON"