#!/bin/bash
echo "=== Exporting merge_vector_layers result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPECTED_TOTAL=$(cat /tmp/expected_feature_count.txt 2>/dev/null || echo "177")

OUTPUT_SHP="/home/ga/gvsig_data/exports/world_merged.shp"

# 1. Check File Existence & Timestamp
if [ -f "$OUTPUT_SHP" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_SHP" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_SHP" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# 2. Analyze Shapefile Content (using ogrinfo inside container)
FEATURE_COUNT="0"
GEOM_TYPE="Unknown"
HAS_ATTRS="false"
CONTINENT_COUNT="0"

if [ "$OUTPUT_EXISTS" = "true" ] && which ogrinfo >/dev/null; then
    # Get basic info
    INFO=$(ogrinfo -so "$OUTPUT_SHP" -al)
    
    # Extract Feature Count
    FEATURE_COUNT=$(echo "$INFO" | grep "Feature Count" | awk '{print $3}')
    
    # Extract Geometry Type
    GEOM_TYPE=$(echo "$INFO" | grep "Geometry:" | awk '{print $2}')
    
    # Check Attributes (look for key columns)
    if echo "$INFO" | grep -q "NAME" && echo "$INFO" | grep -q "CONTINENT"; then
        HAS_ATTRS="true"
    fi
    
    # Check Continent Diversity (SQL query on shapefile)
    # Using ogrinfo -sql to count distinct continents
    # Note: DBF layer name is usually filename without extension
    LAYER_NAME=$(basename "$OUTPUT_SHP" .shp)
    CONTINENTS_LIST=$(ogrinfo -q "$OUTPUT_SHP" -sql "SELECT DISTINCT CONTINENT FROM \"$LAYER_NAME\"" | grep "String =" || true)
    CONTINENT_COUNT=$(echo "$CONTINENTS_LIST" | wc -l)
fi

# 3. Check App Status
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# 4. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "feature_count": ${FEATURE_COUNT:-0},
    "expected_feature_count": $EXPECTED_TOTAL,
    "geometry_type": "$GEOM_TYPE",
    "attributes_preserved": $HAS_ATTRS,
    "distinct_continents": $CONTINENT_COUNT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="