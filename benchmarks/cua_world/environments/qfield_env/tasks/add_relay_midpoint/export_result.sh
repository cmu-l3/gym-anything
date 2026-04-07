#!/system/bin/sh
# Export script for add_relay_midpoint task.
# Checks database state and exports files for verification.

echo "=== Exporting add_relay_midpoint results ==="

GPKG_TARGET="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
RESULT_JSON="/sdcard/task_result.json"

# 1. Take Final Screenshot
screencap -p /sdcard/task_final.png

# 2. Check File Timestamps
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
GPKG_MTIME=$(stat -c %Y "$GPKG_TARGET" 2>/dev/null || echo "0")

FILE_MODIFIED="false"
if [ "$GPKG_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# 3. Query Database (using sqlite3 on Android)
# We export these details to JSON for the host verifier to read,
# OR we copy the GPKG to the host. Copying GPKG is safer for complex verification.
# However, we'll do a quick check here to populate the JSON.

OBS_COUNT="0"
LAST_FEATURE=""
if [ -f "/system/bin/sqlite3" ]; then
    OBS_COUNT=$(/system/bin/sqlite3 "$GPKG_TARGET" "SELECT COUNT(*) FROM field_observations;" 2>/dev/null || echo "0")
    
    # Get the last added feature's details (name|notes|geometry_wkt)
    # Note: QField/QGIS usually adds an 'fid' or 'id' column.
    LAST_FEATURE=$(/system/bin/sqlite3 "$GPKG_TARGET" "SELECT name || '|' || notes FROM field_observations ORDER BY fid DESC LIMIT 1;" 2>/dev/null)
fi

INITIAL_COUNT=$(cat /sdcard/initial_count.txt 2>/dev/null || echo "0")
COUNT_DIFF=$((OBS_COUNT - INITIAL_COUNT))

# 4. Create Result JSON
# We write to a temporary file first
cat > "$RESULT_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "gpkg_mtime": $GPKG_MTIME,
    "file_modified": $FILE_MODIFIED,
    "initial_count": $INITIAL_COUNT,
    "final_count": $OBS_COUNT,
    "count_diff": $COUNT_DIFF,
    "last_feature_summary": "$LAST_FEATURE",
    "screenshot_path": "/sdcard/task_final.png",
    "gpkg_path": "$GPKG_TARGET"
}
EOF

# 5. Prepare files for extraction
# The host `copy_from_env` will pull these files.
# We assume the host pulls from /sdcard/.

echo "Export complete. Result saved to $RESULT_JSON"