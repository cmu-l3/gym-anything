#!/bin/bash
echo "=== Exporting river_floodplain_transects result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Basic file checks
OUTPUT_PATH="/home/ga/GIS_Data/exports/danube_transects.geojson"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE="0"
IS_NEW="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        IS_NEW="true"
    fi
fi

# 3. Advanced GeoJSON Analysis (Python)
# We need to check: valid JSON, feature count, geometry type, coordinate system/units (via line length)
ANALYSIS_JSON="{}"

if [ "$FILE_EXISTS" = "true" ]; then
    ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
import math
import sys

def haversine_length(coords):
    # Rough estimate if coords are in degrees
    total = 0.0
    for i in range(len(coords)-1):
        lon1, lat1 = coords[i]
        lon2, lat2 = coords[i+1]
        R = 6371000 # meters
        phi1 = math.radians(lat1)
        phi2 = math.radians(lat2)
        dphi = math.radians(lat2-lat1)
        dlam = math.radians(lon2-lon1)
        a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2) * math.sin(dlam/2)**2
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
        total += R * c
    return total

def euclidean_length(coords):
    # Simple euclidean distance (for projected CRS)
    total = 0.0
    for i in range(len(coords)-1):
        x1, y1 = coords[i]
        x2, y2 = coords[i+1]
        total += math.sqrt((x2-x1)**2 + (y2-y1)**2)
    return total

try:
    with open("/home/ga/GIS_Data/exports/danube_transects.geojson", "r") as f:
        data = json.load(f)
    
    features = data.get("features", [])
    count = len(features)
    
    if count == 0:
        print(json.dumps({"valid": True, "count": 0, "error": "No features"}))
        sys.exit(0)

    # Check Geometry Type
    geom_types = set()
    lengths = []
    
    # Check Bounding Box (Danube is roughly Longitude 8 to 30, Latitude 43 to 49)
    # If projected (Metric), coords will be huge (e.g. 1,000,000+)
    # If geographic, coords will be small (< 180)
    
    min_x, min_y = float('inf'), float('inf')
    max_x, max_y = float('-inf'), float('-inf')

    for feat in features:
        geom = feat.get("geometry", {})
        if not geom: continue
        
        g_type = geom.get("type")
        geom_types.add(g_type)
        
        coords = geom.get("coordinates", [])
        if g_type == "LineString":
            # Update bbox
            for pt in coords:
                if len(pt) >= 2:
                    min_x = min(min_x, pt[0])
                    max_x = max(max_x, pt[0])
                    min_y = min(min_y, pt[1])
                    max_y = max(max_y, pt[1])
            
            # Calculate length
            # Heuristic to detect CRS
            if abs(coords[0][0]) > 180 or abs(coords[0][1]) > 90:
                # Likely Projected (Meters)
                l = euclidean_length(coords)
                lengths.append(l)
            else:
                # Geographic (Degrees)
                # If user failed to reproject, the '10000' length input might result in 
                # 10000 degrees (huge) or if they used a tool that handles on-the-fly, 
                # it might be correct.
                # However, usually 'Transects' tool uses map units.
                # If map units are degrees, input '10000' -> 10000 degrees -> HUGE.
                # If input '0.1' -> 0.1 degrees -> ~11km.
                # Let's verify standard Euclidean length on the raw coords first.
                l_deg = euclidean_length(coords) 
                lengths.append(l_deg)

    avg_len = sum(lengths)/len(lengths) if lengths else 0
    
    # Determine if coordinates look like meters or degrees
    is_metric_coords = (min_x > 180 or min_x < -180 or min_y > 90 or min_y < -90)
    
    print(json.dumps({
        "valid": True,
        "count": count,
        "geom_types": list(geom_types),
        "avg_length": avg_len,
        "is_metric_coords": is_metric_coords,
        "bbox": [min_x, min_y, max_x, max_y]
    }))

except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
)
fi

# 4. Save Result
# Use temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "is_new": $IS_NEW,
    "analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="