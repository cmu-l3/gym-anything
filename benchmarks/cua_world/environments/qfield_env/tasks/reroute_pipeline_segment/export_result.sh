#!/system/bin/sh
# Export script for reroute_pipeline_segment task
# Runs inside Android emulator

echo "=== Exporting Results ==="

TASK_DIR="/sdcard/tasks/reroute_pipeline_segment"
GPKG_SRC="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
RESULT_JSON="$TASK_DIR/task_result.json"

# 1. Take final screenshot
screencap -p "$TASK_DIR/final_state.png"

# 2. Check if App is running
APP_RUNNING="false"
if dumpsys window | grep mCurrentFocus | grep -q "ch.opengis.qfield"; then
    APP_RUNNING="true"
fi

# 3. Export GeoPackage for verification
# We copy it to the task dir where the host verifier can pull it via copy_from_env
# (assuming copy_from_env can pull from /sdcard/tasks/...)
cp "$GPKG_SRC" "$TASK_DIR/result.gpkg"

# 4. Get file stats
if [ -f "$GPKG_SRC" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(ls -l "$GPKG_SRC" | awk '{print $4}')
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
fi

# 5. Create JSON Result
echo "{" > "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"gpkg_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"gpkg_size\": $FILE_SIZE," >> "$RESULT_JSON"
echo "  \"timestamp\": $(date +%s)" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Export complete. Files ready in $TASK_DIR"