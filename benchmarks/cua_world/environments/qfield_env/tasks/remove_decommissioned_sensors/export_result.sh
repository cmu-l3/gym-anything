#!/system/bin/sh
# Export script for remove_decommissioned_sensors task
# Runs inside the Android environment

echo "=== Exporting Task Result ==="

# Paths
PACKAGE="ch.opengis.qfield"
WORK_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
RESULT_GPKG="/sdcard/result_world_survey.gpkg"
RESULT_JSON="/sdcard/task_result.json"
FINAL_SCREENSHOT="/sdcard/task_final.png"
TIMESTAMP_FILE="/sdcard/task_start_time.txt"

# 1. Capture Final Screenshot
screencap -p "$FINAL_SCREENSHOT"

# 2. Export the GeoPackage for verification
# We copy it to /sdcard root so the verifier can pull it easily
if [ -f "$WORK_GPKG" ]; then
    cp "$WORK_GPKG" "$RESULT_GPKG"
    chmod 666 "$RESULT_GPKG"
    GPKG_EXISTS="true"
    GPKG_SIZE=$(stat -c %s "$RESULT_GPKG")
else
    GPKG_EXISTS="false"
    GPKG_SIZE=0
fi

# 3. Check App State
APP_RUNNING=$(pidof $PACKAGE > /dev/null && echo "true" || echo "false")

# 4. Get Timestamps
TASK_START=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo "0")
TASK_END=$(date +%s)
FILE_MTIME=$(stat -c %Y "$WORK_GPKG" 2>/dev/null || echo "0")

FILE_MODIFIED="false"
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# 5. Create Result JSON
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"task_end\": $TASK_END," >> "$RESULT_JSON"
echo "  \"gpkg_exists\": $GPKG_EXISTS," >> "$RESULT_JSON"
echo "  \"gpkg_size\": $GPKG_SIZE," >> "$RESULT_JSON"
echo "  \"file_modified\": $FILE_MODIFIED," >> "$RESULT_JSON"
echo "  \"app_was_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"gpkg_path\": \"$RESULT_GPKG\"," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"$FINAL_SCREENSHOT\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result JSON saved to $RESULT_JSON"
cat "$RESULT_JSON"

echo "=== Export Complete ==="