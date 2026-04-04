#!/bin/bash
echo "=== Exporting Identify Flood-Safe Cities Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

BUFFER_PATH="/home/ga/gvsig_data/exports/river_buffer_05deg.shp"
RESULT_PATH="/home/ga/gvsig_data/exports/safe_cities.shp"

# Take final screenshot
take_screenshot /tmp/task_final.png

# ----------------------------------------------------------------
# ANALYZE BUFFER FILE
# ----------------------------------------------------------------
BUFFER_EXISTS="false"
BUFFER_CREATED_DURING_TASK="false"
BUFFER_GEOMETRY="unknown"

if [ -f "$BUFFER_PATH" ]; then
    BUFFER_EXISTS="true"
    BUFFER_MTIME=$(stat -c %Y "$BUFFER_PATH" 2>/dev/null || echo "0")
    if [ "$BUFFER_MTIME" -gt "$TASK_START" ]; then
        BUFFER_CREATED_DURING_TASK="true"
    fi
    
    # Check geometry type using ogrinfo
    BUFFER_INFO=$(ogrinfo -so -al "$BUFFER_PATH" | grep "Geometry:" || echo "")
    if [[ "$BUFFER_INFO" == *"Polygon"* ]]; then
        BUFFER_GEOMETRY="Polygon"
    fi
fi

# ----------------------------------------------------------------
# ANALYZE RESULT FILE (SAFE CITIES)
# ----------------------------------------------------------------
RESULT_EXISTS="false"
RESULT_CREATED_DURING_TASK="false"
RESULT_FEATURE_COUNT=0
INCLUDED_CITIES=()
EXCLUDED_CITIES=()

if [ -f "$RESULT_PATH" ]; then
    RESULT_EXISTS="true"
    RESULT_MTIME=$(stat -c %Y "$RESULT_PATH" 2>/dev/null || echo "0")
    if [ "$RESULT_MTIME" -gt "$TASK_START" ]; then
        RESULT_CREATED_DURING_TASK="true"
    fi

    # Get feature count
    RESULT_FEATURE_COUNT=$(ogrinfo -so -al "$RESULT_PATH" | grep "Feature Count" | cut -d: -f2 | tr -d ' ' || echo "0")
    
    # Check for specific cities in the output (Name Check)
    # Dump attributes to a temp file
    ogrinfo -al "$RESULT_PATH" > /tmp/cities_dump.txt
    
    # Check inclusions
    for city in "Santiago" "Lima" "Bogota" "Caracas"; do
        if grep -q "$city" /tmp/cities_dump.txt; then
            INCLUDED_CITIES+=("$city")
        fi
    done
    
    # Check exclusions (Manaus should NOT be there)
    for city in "Manaus" "Paris" "New York"; do
        if ! grep -q "$city" /tmp/cities_dump.txt; then
            EXCLUDED_CITIES+=("$city")
        fi
    done
fi

# ----------------------------------------------------------------
# CREATE JSON RESULT
# ----------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "buffer_exists": $BUFFER_EXISTS,
    "buffer_created_during_task": $BUFFER_CREATED_DURING_TASK,
    "buffer_geometry": "$BUFFER_GEOMETRY",
    "result_exists": $RESULT_EXISTS,
    "result_created_during_task": $RESULT_CREATED_DURING_TASK,
    "result_feature_count": $RESULT_FEATURE_COUNT,
    "included_cities": $(printf '%s\n' "${INCLUDED_CITIES[@]}" | jq -R . | jq -s .),
    "excluded_cities_correctly": $(printf '%s\n' "${EXCLUDED_CITIES[@]}" | jq -R . | jq -s .),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON created at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="