#!/bin/bash
echo "=== Exporting spatial_trend_ellipse_japan result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi

# 1. Capture Final State
take_screenshot /tmp/task_end.png

# 2. Define Paths
OUTPUT_FILE="/home/ga/GIS_Data/exports/japan_urban_trend.geojson"
TASK_START_TIMESTAMP=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 3. Basic File Checks
FILE_EXISTS="false"
FILE_SIZE=0
FILE_NEW="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START_TIMESTAMP" ]; then
        FILE_NEW="true"
    fi
else
    # Check for alternative filenames (fuzzy search)
    ALT_FILE=$(find /home/ga/GIS_Data/exports -name "*japan*" -name "*.geojson" -newermt "@$TASK_START_TIMESTAMP" 2>/dev/null | head -1)
    if [ -n "$ALT_FILE" ]; then
        OUTPUT_FILE="$ALT_FILE"
        FILE_EXISTS="true"
        FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
        FILE_NEW="true"
    fi
fi

# 4. Deep Analysis with Python
# We analyze the GeoJSON to verify geometry, location, and attributes
ANALYSIS_JSON=$(python3 << PYEOF
import json
import sys
import math

result = {
    "valid_geojson": False,
    "feature_count": 0,
    "geometry_type": None,
    "centroid_lon": 0.0,
    "centroid_lat": 0.0,
    "has_stat_attributes": False,
    "is_circle": False,
    "error": None
}

try:
    file_path = "$OUTPUT_FILE"
    with open(file_path, 'r') as f:
        data = json.load(f)
    
    if data.get("type") == "FeatureCollection":
        result["valid_geojson"] = True
        features = data.get("features", [])
        result["feature_count"] = len(features)
        
        if len(features) > 0:
            feat = features[0]
            geom = feat.get("geometry", {})
            props = feat.get("properties", {})
            
            result["geometry_type"] = geom.get("type")
            
            # Check for standard deviational ellipse attributes
            # QGIS typically adds CenterX, CenterY, StdDev, Angle, Area, Perimeter, etc.
            # OR Weight, etc. Exact names vary by version, but usually include 'CenterX' or 'Area'
            keys = [k.lower() for k in props.keys()]
            if any(k in keys for k in ['centerx', 'centery', 'stddev', 'angle', 'area', 'perimeter']):
                result["has_stat_attributes"] = True
            
            # Calculate simple centroid of the polygon to verify location
            if geom.get("type") == "Polygon":
                coords = geom.get("coordinates", [])[0] # Outer ring
                if coords:
                    # Simple average of vertices
                    sum_x = sum(p[0] for p in coords)
                    sum_y = sum(p[1] for p in coords)
                    result["centroid_lon"] = sum_x / len(coords)
                    result["centroid_lat"] = sum_y / len(coords)
                    
                    # Check if it's a circle (width approx equal to height)
                    min_x = min(p[0] for p in coords)
                    max_x = max(p[0] for p in coords)
                    min_y = min(p[1] for p in coords)
                    max_y = max(p[1] for p in coords)
                    
                    width = max_x - min_x
                    height = max_y - min_y
                    
                    # If ratio is very close to 1, it might be a circle (buffer) instead of ellipse
                    # But aspect ratio depends on latitude too. 
                    # Better check: StdDev ellipse usually has rotation.
                    
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
)

# 5. Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# 6. Save Result
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_path": "$OUTPUT_FILE",
    "file_size": $FILE_SIZE,
    "file_new": $FILE_NEW,
    "analysis": $ANALYSIS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="