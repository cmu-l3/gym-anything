#!/system/bin/sh
# Export script for delete_feature task.
# Collects timestamps, final screenshot, and metadata.
# The actual GPKG verification happens on the host in verifier.py.

echo "=== Exporting delete_feature results ==="

TASK_INFO_DIR="/data/local/tmp"
RESULT_JSON="$TASK_INFO_DIR/task_result.json"
WORKING_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"

# 1. Capture Final Screenshot
screencap -p "$TASK_INFO_DIR/task_final.png"

# 2. Check File Timestamps
TASK_START=$(cat "$TASK_INFO_DIR/task_start_time.txt" 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)
FILE_MOD_TIME=0
FILE_EXISTS="false"

if [ -f "$WORKING_GPKG" ]; then
    FILE_EXISTS="true"
    # Get modification time in epoch seconds (stat in Android toolbox can vary, using ls -l as fallback if needed)
    FILE_MOD_TIME=$(stat -c %Y "$WORKING_GPKG" 2>/dev/null)
fi

# 3. Check if App is Running
APP_RUNNING="false"
if ps -A | grep -q "ch.opengis.qfield"; then
    APP_RUNNING="true"
fi

# 4. Create Result JSON
# We construct JSON manually since jq might not be available on Android
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"task_end\": $CURRENT_TIME," >> "$RESULT_JSON"
echo "  \"gpkg_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"gpkg_mtime\": $FILE_MOD_TIME," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"gpkg_path\": \"$WORKING_GPKG\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

# Set permissions so host can pull
chmod 666 "$RESULT_JSON"
chmod 666 "$TASK_INFO_DIR/task_final.png"

echo "Export complete. Result saved to $RESULT_JSON"
cat "$RESULT_JSON"