#!/system/bin/sh
echo "=== Exporting task results ==="

# Define paths
GPKG_PATH="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
RESULT_JSON="/sdcard/task_result.json"

# Capture timestamps
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Capture final screenshot
screencap -p /sdcard/task_final.png

# Check file stats
if [ -f "$GPKG_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$GPKG_PATH")
    FILE_MTIME=$(stat -c %Y "$GPKG_PATH")
    
    # Check if modified during task
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        MODIFIED="true"
    else
        MODIFIED="false"
    fi
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    MODIFIED="false"
fi

# Create simple JSON for export (since jq might not be available on Android)
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"task_end\": $TASK_END," >> "$RESULT_JSON"
echo "  \"gpkg_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"gpkg_modified\": $MODIFIED," >> "$RESULT_JSON"
echo "  \"gpkg_path\": \"$GPKG_PATH\"," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"