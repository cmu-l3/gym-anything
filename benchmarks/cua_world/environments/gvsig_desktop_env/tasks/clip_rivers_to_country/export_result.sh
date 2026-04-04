#!/bin/bash
echo "=== Exporting clip_rivers_to_country result ==="

source /workspace/scripts/task_utils.sh

# Paths
OUTPUT_SHP="/home/ga/gvsig_data/exports/brazil_rivers.shp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check File Existence & Timestamp
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$OUTPUT_SHP" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_SHP")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_SHP")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Analyze Shapefile with ogrinfo (if file exists)
FEATURE_COUNT=0
GEOMETRY_TYPE="Unknown"
EXTENT="0, 0, 0, 0"
IS_VALID="false"

if [ "$FILE_EXISTS" = "true" ]; then
    echo "Analyzing shapefile with ogrinfo..."
    
    # Get Info
    INFO=$(ogrinfo -so -al "$OUTPUT_SHP")
    
    if [ $? -eq 0 ]; then
        IS_VALID="true"
        
        # Extract Feature Count
        FEATURE_COUNT=$(echo "$INFO" | grep "Feature Count:" | awk '{print $3}')
        
        # Extract Geometry
        GEOMETRY_TYPE=$(echo "$INFO" | grep "Geometry:" | awk '{print $2}')
        
        # Extract Extent
        # Format: Extent: (-73.990449, -33.752081) - (-34.792916, 5.271841)
        EXTENT=$(echo "$INFO" | grep "Extent:" | sed 's/Extent: //')
    fi
fi

# 4. Get Original Rivers Count (for comparison)
ORIG_RIVERS="/home/ga/gvsig_data/rivers/ne_110m_rivers_lake_centerlines.shp"
ORIG_COUNT=0
if [ -f "$ORIG_RIVERS" ]; then
    ORIG_COUNT=$(ogrinfo -so -al "$ORIG_RIVERS" | grep "Feature Count:" | awk '{print $3}')
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "is_valid": $IS_VALID,
    "feature_count": ${FEATURE_COUNT:-0},
    "original_count": ${ORIG_COUNT:-0},
    "geometry_type": "$GEOMETRY_TYPE",
    "extent_raw": "$EXTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export complete ==="