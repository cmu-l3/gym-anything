#!/system/bin/sh
# Export script for map_seismic_antipode task
# Captures final state and metadata

echo "=== Exporting task results ==="

GPKG_TASK="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
RESULT_JSON="/sdcard/task_result.json"

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 2. Check if file was modified
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
FILE_MTIME=$(stat -c %Y "$GPKG_TASK" 2>/dev/null || echo "0")

MODIFIED="false"
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    MODIFIED="true"
fi

# 3. Create Result JSON
# Note: We can't easily run python or sophisticated json tools in android shell
# So we create a simple JSON string.
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"file_mtime\": $FILE_MTIME," >> "$RESULT_JSON"
echo "  \"file_modified\": $MODIFIED," >> "$RESULT_JSON"
echo "  \"gpkg_path\": \"$GPKG_TASK\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"