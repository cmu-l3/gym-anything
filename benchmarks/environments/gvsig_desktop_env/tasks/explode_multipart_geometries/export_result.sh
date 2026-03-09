#!/bin/bash
echo "=== Exporting explode_multipart_geometries result ==="

source /workspace/scripts/task_utils.sh

# Parameters
OUTPUT_SHP="/home/ga/gvsig_data/exports/countries_singlepart.shp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Initialize result variables
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FEATURE_COUNT=0
GEOMETRY_TYPE="Unknown"
HAS_ATTRIBUTES="false"
INDONESIA_COUNT=0

# 3. Analyze Output File
if [ -f "$OUTPUT_SHP" ]; then
    FILE_EXISTS="true"
    
    # Check timestamps
    FILE_MTIME=$(stat -c %Y "$OUTPUT_SHP" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Use ogrinfo to analyze shapefile
    if command -v ogrinfo &> /dev/null; then
        echo "Analyzing shapefile with ogrinfo..."
        
        # Get basic info (Feature Count, Geometry)
        INFO=$(ogrinfo -so -al "$OUTPUT_SHP")
        
        # Extract Feature Count
        FEATURE_COUNT=$(echo "$INFO" | grep "Feature Count:" | awk '{print $3}')
        
        # Extract Geometry Type
        GEOMETRY_TYPE=$(echo "$INFO" | grep "Geometry:" | awk '{print $2}')
        
        # Check for attributes (NAME, POP_EST)
        if echo "$INFO" | grep -q "NAME: String" && echo "$INFO" | grep -q "POP_EST"; then
            HAS_ATTRIBUTES="true"
        fi
        
        # Check if Indonesia was split (should be > 1 feature with NAME='Indonesia')
        # We query the shapefile for records where NAME = 'Indonesia'
        INDONESIA_INFO=$(ogrinfo -al "$OUTPUT_SHP" -where "NAME='Indonesia'" | grep "Feature Count:")
        INDONESIA_COUNT=$(echo "$INDONESIA_INFO" | awk '{print $3}' || echo "0")
        
        echo "Analysis Results:"
        echo "  Count: $FEATURE_COUNT"
        echo "  Type: $GEOMETRY_TYPE"
        echo "  Attributes: $HAS_ATTRIBUTES"
        echo "  Indonesia Parts: $INDONESIA_COUNT"
    else
        echo "WARNING: ogrinfo not found, cannot perform deep analysis"
    fi
else
    echo "Output file not found at $OUTPUT_SHP"
fi

# 4. Check if gvSIG is still running
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "feature_count": ${FEATURE_COUNT:-0},
    "geometry_type": "${GEOMETRY_TYPE:-Unknown}",
    "attributes_preserved": $HAS_ATTRIBUTES,
    "indonesia_part_count": ${INDONESIA_COUNT:-0},
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save result (handle permissions)
RESULT_PATH="/tmp/task_result.json"
rm -f "$RESULT_PATH" 2>/dev/null || sudo rm -f "$RESULT_PATH" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_PATH"
chmod 666 "$RESULT_PATH"
rm -f "$TEMP_JSON"

echo "Result saved to $RESULT_PATH"
cat "$RESULT_PATH"
echo "=== Export complete ==="