#!/system/bin/sh
echo "=== Exporting task results ==="

# Define paths
TARGET_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
RESULT_JSON="/sdcard/task_result.json"

# Timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /sdcard/initial_count.txt 2>/dev/null || echo "0")

# 1. Check if QField is running
APP_RUNNING=$(pidof ch.opengis.qfield > /dev/null && echo "true" || echo "false")

# 2. Extract data from GeoPackage using sqlite3
# We look for features added AFTER the initial count
# We get the last feature added to field_observations
# Columns: name, description, geometry (blob) - handling geometry in shell is hard,
# so we extract X/Y using ST_X/ST_Y if spatialite loaded, or just assume the app
# stores geometry in standard columns or verify via other attributes first.
# Since standard sqlite3 in android might not have spatialite extension loaded,
# we might need to rely on the 'notes' or specific fields if geometry parsing is complex.
# However, QField/QGIS usually stores geometry in a binary blob.
# LUCKILY, the world_survey.gpkg likely has explicit lat/lon columns or we can check
# if the user entered them? The task asks to "Create a new point".
# QField features usually update a geometry column.
# WITHOUT SPATIALITE, we can't easily parse the blob to get lat/lon in shell.
# STRATEGY: We will dump the entire table row and let the python verifier handle blob parsing if needed,
# OR we can assume if the user followed instructions, they might not have manually entered coords in text fields.
# BUT checking geometry is crucial.
# Workaround: Check if 'fid' increased.

CURRENT_COUNT=$(sqlite3 "$TARGET_GPKG" "SELECT count(*) FROM field_observations;" 2>/dev/null || echo "0")
ADDED_COUNT=$((CURRENT_COUNT - INITIAL_COUNT))

# Retrieve the attributes of the last added feature
# We assume the last ID is the new one.
LAST_FEATURE_JSON=$(sqlite3 "$TARGET_GPKG" "SELECT json_object('name', name, 'description', description, 'notes', notes) FROM field_observations ORDER BY fid DESC LIMIT 1;" 2>/dev/null)

# For geometry, since we can't easily parse GeoPackage binary blobs in pure shell without spatialite,
# we will rely on the Python verifier to parse the GPKG file which we will copy out.
# We will just report the counts here.

# Capture final screenshot
screencap -p /sdcard/task_final.png

# Create JSON output
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "added_count": $ADDED_COUNT,
    "app_was_running": $APP_RUNNING,
    "last_feature_attributes": $LAST_FEATURE_JSON
}
EOF

# Ensure permissions for copy_from_env
chmod 666 "$RESULT_JSON"
chmod 666 "$TARGET_GPKG"
chmod 666 /sdcard/task_final.png

echo "Export complete. Result saved to $RESULT_JSON"