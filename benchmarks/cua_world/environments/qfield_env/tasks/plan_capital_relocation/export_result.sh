#!/system/bin/sh
# Export script for plan_capital_relocation task
# Runs inside Android emulator

echo "=== Exporting Results ==="

# Paths
PACKAGE="ch.opengis.qfield"
WORK_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
EXPORT_DIR="/sdcard/task_results"
EXPORT_GPKG="$EXPORT_DIR/world_survey_final.gpkg"
JSON_RESULT="$EXPORT_DIR/task_result.json"

mkdir -p "$EXPORT_DIR"

# 1. Capture Final Screenshot (Evidence of UI state)
screencap -p "$EXPORT_DIR/task_final.png"

# 2. Force Flush / Stop App
# SQLite wal files might not be committed if app is running
am force-stop $PACKAGE
sleep 2

# 3. Check timestamps for anti-gaming
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
FILE_MTIME=$(stat -c %Y "$WORK_GPKG" 2>/dev/null || echo "0")

MODIFIED_DURING_TASK="false"
if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
    MODIFIED_DURING_TASK="true"
fi

# 4. Copy GPKG for Verification
if [ -f "$WORK_GPKG" ]; then
    cp "$WORK_GPKG" "$EXPORT_GPKG"
    chmod 666 "$EXPORT_GPKG"
    GPKG_EXISTS="true"
    GPKG_SIZE=$(stat -c %s "$EXPORT_GPKG")
else
    GPKG_EXISTS="false"
    GPKG_SIZE="0"
fi

# 5. Create Result JSON
# We write this to a file so the host can pull it via copy_from_env
echo "{" > "$JSON_RESULT"
echo "  \"task_start\": $TASK_START," >> "$JSON_RESULT"
echo "  \"gpkg_exists\": $GPKG_EXISTS," >> "$JSON_RESULT"
echo "  \"gpkg_path\": \"$EXPORT_GPKG\"," >> "$JSON_RESULT"
echo "  \"gpkg_size\": $GPKG_SIZE," >> "$JSON_RESULT"
echo "  \"modified_during_task\": $MODIFIED_DURING_TASK," >> "$JSON_RESULT"
echo "  \"screenshot_path\": \"$EXPORT_DIR/task_final.png\"" >> "$JSON_RESULT"
echo "}" >> "$JSON_RESULT"

echo "Export complete. JSON result:"
cat "$JSON_RESULT"