#!/system/bin/sh
# Export script for mark_equatorial_hubs task
# Android environment

echo "=== Exporting results ==="

GPKG_PATH="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
TASK_START=$(cat /data/local/tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check File Stats
if [ -f "$GPKG_PATH" ]; then
    GPKG_EXISTS="true"
    GPKG_SIZE=$(stat -c %s "$GPKG_PATH")
    GPKG_MTIME=$(stat -c %Y "$GPKG_PATH")
else
    GPKG_EXISTS="false"
    GPKG_SIZE="0"
    GPKG_MTIME="0"
fi

# 2. Check Feature Count Change (Anti-gaming)
INITIAL_COUNT=$(cat /data/local/tmp/initial_count.txt 2>/dev/null || echo "0")
FINAL_COUNT="0"

if [ "$GPKG_EXISTS" = "true" ] && command -v sqlite3 >/dev/null 2>&1; then
    FINAL_COUNT=$(sqlite3 "$GPKG_PATH" "SELECT COUNT(*) FROM field_observations;" 2>/dev/null || echo "0")
fi

# 3. Take Final Screenshot
screencap -p /data/local/tmp/task_final.png

# 4. Create JSON Result
# We use a temp file in a writable location
TEMP_JSON="/data/local/tmp/task_result.json"

echo "{" > "$TEMP_JSON"
echo "  \"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "  \"task_end\": $TASK_END," >> "$TEMP_JSON"
echo "  \"gpkg_exists\": $GPKG_EXISTS," >> "$TEMP_JSON"
echo "  \"gpkg_path\": \"$GPKG_PATH\"," >> "$TEMP_JSON"
echo "  \"gpkg_mtime\": $GPKG_MTIME," >> "$TEMP_JSON"
echo "  \"initial_count\": $INITIAL_COUNT," >> "$TEMP_JSON"
echo "  \"final_count\": $FINAL_COUNT," >> "$TEMP_JSON"
echo "  \"screenshot_path\": \"/data/local/tmp/task_final.png\"" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

# Ensure permissions for extraction
chmod 666 "$TEMP_JSON"
chmod 666 /data/local/tmp/task_final.png

echo "=== Export complete ==="
cat "$TEMP_JSON"