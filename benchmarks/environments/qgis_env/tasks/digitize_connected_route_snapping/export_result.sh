#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Output file path
OUTPUT_PATH="/home/ga/GIS_Data/power_line.gpkg"

# Check file stats
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
fi

# Analyze geometry using Python (fiona/shapely are available in env)
# We extract the coordinates to avoid having to parse binary GPKG in the verifier
echo "Analyzing geometry..."
ANALYSIS=$(python3 << 'PYEOF'
import sys
import json
try:
    import fiona
    from shapely.geometry import shape
    
    file_path = "/home/ga/GIS_Data/power_line.gpkg"
    result = {
        "valid_layer": False,
        "feature_count": 0,
        "geom_type": None,
        "coordinates": [],
        "crs": None
    }
    
    try:
        # Open the layer (fiona usually auto-detects the first layer)
        with fiona.open(file_path, 'r') as source:
            result["valid_layer"] = True
            result["feature_count"] = len(source)
            result["crs"] = str(source.crs)
            
            if len(source) > 0:
                # Get the first feature
                feat = next(iter(source))
                geom = shape(feat['geometry'])
                result["geom_type"] = geom.geom_type
                
                if geom.geom_type == 'LineString':
                    result["coordinates"] = list(geom.coords)
                elif geom.geom_type == 'MultiLineString':
                    # Just take the first part
                    result["coordinates"] = list(geom.geoms[0].coords)
                    
    except Exception as e:
        result["error"] = str(e)

    print(json.dumps(result))
    
except ImportError:
    # Fallback if libraries missing (unlikely in qgis_env)
    print(json.dumps({"error": "libraries_missing"}))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
)

# Check if QGIS is running
APP_RUNNING=$(pgrep -f "qgis" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "geometry_analysis": $ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="