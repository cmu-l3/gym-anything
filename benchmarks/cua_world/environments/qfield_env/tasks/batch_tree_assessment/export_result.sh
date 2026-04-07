#!/system/bin/sh
echo "=== Exporting batch_tree_assessment results ==="

PACKAGE="ch.opengis.qfield"
GPKG_PATH="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
RESULT_JSON="/sdcard/task_result.json"

# 1. Capture Final Screenshot (before stopping app)
screencap -p /sdcard/task_final.png

# 2. Check App State
APP_RUNNING=$(pidof ch.opengis.qfield > /dev/null && echo "true" || echo "false")

# 3. Force Stop to flush SQLite WAL (Write-Ahead Log) to disk
# CRITICAL: If we don't do this, recent edits might sit in .gpkg-wal and not be in .gpkg
am force-stop $PACKAGE
sleep 2

# 4. Gather File Metadata
if [ -f "$GPKG_PATH" ]; then
    GPKG_EXISTS="true"
    GPKG_SIZE=$(stat -c %s "$GPKG_PATH" 2>/dev/null || echo "0")
    GPKG_MTIME=$(stat -c %Y "$GPKG_PATH" 2>/dev/null || echo "0")
else
    GPKG_EXISTS="false"
    GPKG_SIZE="0"
    GPKG_MTIME="0"
fi

TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /sdcard/initial_observation_count.txt 2>/dev/null || echo "8")

# 5. Create Result JSON
# We don't query SQLite here (we do it in python verifier).
# We just export the metadata needed to find the file.
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"gpkg_exists\": $GPKG_EXISTS," >> "$RESULT_JSON"
echo "  \"gpkg_path\": \"$GPKG_PATH\"," >> "$RESULT_JSON"
echo "  \"gpkg_mtime\": $GPKG_MTIME," >> "$RESULT_JSON"
echo "  \"initial_count\": $INITIAL_COUNT," >> "$RESULT_JSON"
echo "  \"app_was_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"final_screenshot\": \"/sdcard/task_final.png\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

# Set permissions so we can copy it out
chmod 666 "$RESULT_JSON" 2>/dev/null || true
chmod 666 "$GPKG_PATH" 2>/dev/null || true

echo "=== Export complete ==="
cat "$RESULT_JSON"