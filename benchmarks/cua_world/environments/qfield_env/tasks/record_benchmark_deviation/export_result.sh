#!/system/bin/sh
# Export script for record_benchmark_deviation task.
# queries the GeoPackage for results and saves to a JSON-like structure.

echo "=== Exporting task results ==="

GPKG_TASK="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
RESULT_FILE="/data/local/tmp/task_result.json"

# 1. Capture Final Screenshot
# The framework usually handles this, but we ensure one exists for the record
screencap -p /data/local/tmp/task_final.png

# 2. Query the GeoPackage for the specific feature
# We look for the most recently added feature or one named 'QA_Log_Cairo'

# Get the count of observations now
FINAL_COUNT=$(sqlite3 "$GPKG_TASK" "SELECT COUNT(*) FROM field_observations;" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /data/local/tmp/initial_count.txt 2>/dev/null || echo "0")

# Extract the target feature data (Name, Description, Geometry X, Geometry Y)
# We select the feature named 'QA_Log_Cairo'
# Note: ST_X and ST_Y might be available if spatialite is loaded, otherwise we might rely on the fact 
# that QField works. If sqlite3 in this env is bare, we might only get attributes. 
# However, standard QField/Android sqlite3 usually supports basic spatialite functions or blobs.
# We will try to get attributes primarily.

FEATURE_DATA=$(sqlite3 -header -json "$GPKG_TASK" "SELECT name, notes, description, ST_X(geom) as x, ST_Y(geom) as y FROM field_observations WHERE name LIKE '%QA_Log_Cairo%' ORDER BY fid DESC LIMIT 1;" 2>/dev/null)

if [ -z "$FEATURE_DATA" ]; then
    # Fallback: try just getting the last feature if name didn't match perfectly but count increased
    if [ "$FINAL_COUNT" -gt "$INITIAL_COUNT" ]; then
        FEATURE_DATA=$(sqlite3 -header -json "$GPKG_TASK" "SELECT name, notes, description, ST_X(geom) as x, ST_Y(geom) as y FROM field_observations ORDER BY fid DESC LIMIT 1;" 2>/dev/null)
    fi
fi

# 3. Extract the ground truth coordinate for Cairo from the map itself
# This allows the verifier to calculate the EXACT deviation based on the map's internal data
CAIRO_DATA=$(sqlite3 -header -json "$GPKG_TASK" "SELECT name, ST_X(geom) as x, ST_Y(geom) as y FROM world_capitals WHERE name='Cairo';" 2>/dev/null)

# 4. Construct JSON output manually since we are in a restricted shell
# We write the raw json parts to a file and wrap them
echo "{" > "$RESULT_FILE"
echo "  \"initial_count\": $INITIAL_COUNT," >> "$RESULT_FILE"
echo "  \"final_count\": $FINAL_COUNT," >> "$RESULT_FILE"
echo "  \"feature_data\": ${FEATURE_DATA:-null}," >> "$RESULT_FILE"
echo "  \"cairo_data\": ${CAIRO_DATA:-null}," >> "$RESULT_FILE"
echo "  \"timestamp\": $(date +%s)" >> "$RESULT_FILE"
echo "}" >> "$RESULT_FILE"

# 5. Set permissions so the host can pull it
chmod 666 "$RESULT_FILE"
chmod 666 /data/local/tmp/task_final.png

echo "Export complete. Result stored in $RESULT_FILE"
cat "$RESULT_FILE"