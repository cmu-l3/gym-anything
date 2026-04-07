#!/system/bin/sh
echo "=== Exporting define_service_bounds results ==="

PACKAGE="ch.opengis.qfield"
PROJECT_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
TARGET_GPKG="$PROJECT_DIR/world_survey.gpkg"
RESULT_JSON="/sdcard/task_result.json"
FINAL_SCREENSHOT="/sdcard/task_final.png"

# 1. Force stop QField to ensure SQLite WAL is flushed to disk
echo "Closing QField to flush database..."
am force-stop $PACKAGE
sleep 2

# 2. Capture Final Screenshot (using screencap on Android)
echo "Capturing final state..."
screencap -p "$FINAL_SCREENSHOT"

# 3. Check file timestamps
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
FILE_MODIFIED="false"

if [ -f "$TARGET_GPKG" ]; then
    # Android's stat might differ, using simplistic check or assuming modified if WAL existed
    # In simple envs, we just check if it exists. Verification does logic check.
    # Note: determining exact modification time in standard Android shell can be tricky 
    # if 'stat' is limited. We'll rely on the verifier checking the DB content vs fresh.
    FILE_MODIFIED="true"
fi

# 4. Prepare Result JSON
# We don't have python in the android env usually, so we create a simple JSON string
echo "{\"task_start\": $TASK_START, \"gpkg_path\": \"$TARGET_GPKG\", \"screenshot_path\": \"$FINAL_SCREENSHOT\"}" > "$RESULT_JSON"

# 5. Make files accessible
chmod 666 "$RESULT_JSON"
chmod 666 "$TARGET_GPKG"
chmod 666 "$FINAL_SCREENSHOT"

echo "=== Export complete ==="