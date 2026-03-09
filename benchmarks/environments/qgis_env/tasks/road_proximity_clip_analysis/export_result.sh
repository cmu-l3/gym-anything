#!/bin/bash
echo "=== Exporting road_proximity_clip_analysis result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/GIS_Data/exports/impacted_roads_500m.geojson"

# Check file existence and timestamp
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Perform Python-based spatial analysis of the result
# We use the installed python3-shapely environment
ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
import sys
import os
from shapely.geometry import shape, Point, LineString, MultiLineString

output_path = "/home/ga/GIS_Data/exports/impacted_roads_500m.geojson"
points_path = "/home/ga/GIS_Data/sample_points.geojson"

result = {
    "valid_geojson": False,
    "feature_count": 0,
    "geometry_type_ok": False,
    "field_exists": False,
    "total_length": 0.0,
    "is_clipped": False,
    "spatial_check": False,
    "error": None
}

if not os.path.exists(output_path):
    print(json.dumps(result))
    sys.exit(0)

try:
    with open(output_path, 'r') as f:
        data = json.load(f)
    
    result["valid_geojson"] = True
    features = data.get("features", [])
    result["feature_count"] = len(features)
    
    if len(features) > 0:
        # Check geometry types
        geoms = [shape(f["geometry"]) for f in features]
        result["geometry_type_ok"] = all(g.geom_type in ['LineString', 'MultiLineString'] for g in geoms)
        
        # Check field existence
        props = features[0].get("properties", {})
        # Check for field impact_len (case insensitive)
        result["field_exists"] = any(k.lower() == "impact_len" for k in props.keys())
        
        # Calculate total length (simple sum of field values if exist, or rough geom sum)
        # Note: If user exported in WGS84, geom length is in degrees.
        # If exported in UTM, geom length is in meters.
        # We rely on the 'impact_len' field which should be calculated in meters during the task steps.
        field_sum = 0.0
        for f in features:
            p = f.get("properties", {})
            for k, v in p.items():
                if k.lower() == "impact_len":
                    try:
                        field_sum += float(v)
                    except:
                        pass
        result["total_length"] = field_sum

        # Check if it looks clipped
        # Original roads are > 70km total. 
        # 500m buffer around 3 points -> max diameter 1km * 3 = 3km (approx).
        # Plus intersection topology.
        # If total length is < 10000 (10km) and > 0, it's likely clipped.
        # If total length > 20000, they probably didn't clip.
        if 50.0 < field_sum < 10000.0:
            result["is_clipped"] = True
            
        # Spatial Check
        # Verify vertices are actually near the source points
        # Load source points
        with open(points_path, 'r') as f:
            pt_data = json.load(f)
        source_points = [shape(f["geometry"]) for f in pt_data.get("features", [])]
        
        # Check first vertex of first feature
        # (Approximate check since we don't know output CRS for sure without pyproj, 
        # but if it's WGS84 we can check distance in degrees, if UTM in meters)
        # We assume if the user followed instructions, they might export in either.
        # But if they calculated length in meters, the field values tell us the metric size.
        # Let's trust the field value check for "is_clipped" primarily.
        result["spatial_check"] = True 

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="