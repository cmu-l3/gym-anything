#!/bin/bash
echo "=== Exporting extract_index_contours_elevation result ==="

source /workspace/scripts/task_utils.sh

# Define paths
EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_FILE="$EXPORT_DIR/index_contours.geojson"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check file existence
if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi

    # Python analysis of the GeoJSON content
    ANALYSIS=$(python3 << 'PYEOF'
import json
import sys
import numpy as np

try:
    with open("/home/ga/GIS_Data/exports/index_contours.geojson") as f:
        data = json.load(f)

    if data.get("type") != "FeatureCollection":
        print('{"valid": false, "error": "Not a FeatureCollection"}')
        sys.exit(0)

    features = data.get("features", [])
    feature_count = len(features)
    
    if feature_count == 0:
        print('{"valid": true, "feature_count": 0, "all_lines": false, "elev_field_found": false}')
        sys.exit(0)

    # Check Geometry Type
    all_lines = all(f.get("geometry", {}).get("type") in ["LineString", "MultiLineString"] for f in features)
    
    # Check Attributes
    elev_values = []
    elev_field_found = False
    
    # Find the elevation field (case insensitive)
    first_props = features[0].get("properties", {})
    keys = list(first_props.keys())
    elev_key = next((k for k in keys if "elev" in k.lower()), None)
    
    if elev_key:
        elev_field_found = True
        for f in features:
            val = f.get("properties", {}).get(elev_key)
            if val is not None:
                try:
                    elev_values.append(float(val))
                except:
                    pass

    # Analysis of values
    if elev_values:
        min_val = min(elev_values)
        max_val = max(elev_values)
        # Check divisibility by 100 (Index Contours)
        # Allow small floating point epsilon, though QGIS contours are usually integers
        all_divisible = all(abs(v % 100) < 0.01 or abs(v % 100 - 100) < 0.01 for v in elev_values)
        some_divisible = any(abs(v % 100) < 0.01 for v in elev_values)
        
        # Check divisibility by 20 (Base Interval) to see if they just dumped everything
        all_base_interval = all(abs(v % 20) < 0.01 for v in elev_values)
    else:
        min_val = 0
        max_val = 0
        all_divisible = False
        some_divisible = False
        all_base_interval = False

    result = {
        "valid": True,
        "feature_count": feature_count,
        "all_lines": all_lines,
        "elev_field_found": elev_field_found,
        "elev_field_name": elev_key,
        "min_val": min_val,
        "max_val": max_val,
        "all_index_contours": all_divisible,
        "mixed_contours": (not all_divisible) and some_divisible,
        "all_base_contours": all_base_interval
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    CREATED_DURING_TASK="false"
    ANALYSIS='{"valid": false}'
fi

# Clean up QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# Write result JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "analysis": $ANALYSIS,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="