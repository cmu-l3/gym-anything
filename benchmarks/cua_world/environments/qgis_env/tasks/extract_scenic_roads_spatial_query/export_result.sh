#!/bin/bash
echo "=== Exporting extract_scenic_roads result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

OUTPUT_PATH="/home/ga/GIS_Data/exports/scenic_roads.geojson"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Default values
FILE_EXISTS="false"
FILE_SIZE=0
IS_NEW="false"
ANALYSIS_JSON="{}"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH")

    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        IS_NEW="true"
    fi

    # Analyze GeoJSON content using Python
    # Checks: Valid JSON, Feature Collection, Geometry Types, Count
    ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/GIS_Data/exports/scenic_roads.geojson", "r") as f:
        data = json.load(f)

    if data.get("type") != "FeatureCollection":
        print(json.dumps({"valid": False, "error": "Not a FeatureCollection"}))
        sys.exit(0)

    features = data.get("features", [])
    count = len(features)
    
    if count == 0:
        print(json.dumps({"valid": True, "count": 0, "geometry_types": []}))
        sys.exit(0)

    # Check geometries
    geom_types = set()
    attributes = set()
    
    # Check first feature for attributes
    if count > 0:
        attributes = set(features[0].get("properties", {}).keys())

    for feat in features[:100]:  # Check first 100 features
        geom = feat.get("geometry")
        if geom:
            geom_types.add(geom.get("type"))
    
    print(json.dumps({
        "valid": True,
        "count": count,
        "geometry_types": list(geom_types),
        "attributes": list(attributes)
    }))

except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "is_new": $IS_NEW,
    "analysis": $ANALYSIS_JSON,
    "timestamp": $CURRENT_TIME
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json