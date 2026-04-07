#!/system/bin/sh
echo "=== Exporting identify_nearest_capital result ==="

PACKAGE="ch.opengis.qfield"
GPKG_PATH="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
RESULT_JSON="/sdcard/task_result.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# capture final screenshot
screencap -p /sdcard/task_final.png

# Check if app is running (in foreground)
APP_RUNNING="false"
if dumpsys window | grep mCurrentFocus | grep -q "$PACKAGE"; then
    APP_RUNNING="true"
fi

# Basic file checks
GPKG_EXISTS="false"
GPKG_SIZE="0"
if [ -f "$GPKG_PATH" ]; then
    GPKG_EXISTS="true"
    GPKG_SIZE=$(ls -l "$GPKG_PATH" | awk '{print $4}')
fi

# Create a simple JSON result file
# We will do the heavy lifting (SQLite analysis) in the host python verifier
# by copying the GPKG file out. This script just provides metadata.
echo "{
    \"task_start\": $TASK_START,
    \"task_end\": $TASK_END,
    \"app_running\": $APP_RUNNING,
    \"gpkg_exists\": $GPKG_EXISTS,
    \"gpkg_size_bytes\": $GPKG_SIZE,
    \"gpkg_path\": \"$GPKG_PATH\",
    \"screenshot_path\": \"/sdcard/task_final.png\"
}" > "$RESULT_JSON"

chmod 666 "$RESULT_JSON"

echo "Result JSON saved to $RESULT_JSON"
echo "=== Export complete ==="