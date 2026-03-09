#!/bin/bash
echo "=== Exporting identify_cities_near_borders result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/gvsig_data/exports/border_cities.shp"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE_BYTES="0"
FEATURE_COUNT="0"
GEOMETRY_TYPE="Unknown"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE_BYTES=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Use python + pyshp to analyze the shapefile content
    # We output a JSON object from python that we can merge into our result
    PYTHON_ANALYSIS=$(python3 -c "
import sys
import json
try:
    import shapefile
    sf = shapefile.Reader('$OUTPUT_PATH')
    print(json.dumps({
        'feature_count': len(sf.shapes()),
        'geometry_type': sf.shapeType,
        'bbox': sf.bbox,
        'valid': True
    }))
except Exception as e:
    print(json.dumps({
        'feature_count': 0,
        'geometry_type': 0,
        'valid': False,
        'error': str(e)
    }))
" 2>/dev/null)
    
    # Extract values from python output
    if [ -n "$PYTHON_ANALYSIS" ]; then
        FEATURE_COUNT=$(echo "$PYTHON_ANALYSIS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('feature_count', 0))")
        # Shapefile Type 1=Point, 3=PolyLine, 5=Polygon, 8=MultiPoint
        GEO_TYPE_CODE=$(echo "$PYTHON_ANALYSIS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('geometry_type', 0))")
        if [ "$GEO_TYPE_CODE" -eq 1 ] || [ "$GEO_TYPE_CODE" -eq 8 ] || [ "$GEO_TYPE_CODE" -eq 11 ] || [ "$GEO_TYPE_CODE" -eq 21 ]; then
            GEOMETRY_TYPE="Point"
        elif [ "$GEO_TYPE_CODE" -eq 3 ] || [ "$GEO_TYPE_CODE" -eq 13 ]; then
            GEOMETRY_TYPE="Line"
        elif [ "$GEO_TYPE_CODE" -eq 5 ] || [ "$GEO_TYPE_CODE" -eq 15 ]; then
            GEOMETRY_TYPE="Polygon"
        fi
    fi
fi

# App running status
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE_BYTES,
    "feature_count": $FEATURE_COUNT,
    "geometry_type": "$GEOMETRY_TYPE",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="