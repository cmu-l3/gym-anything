#!/bin/bash
echo "=== Exporting Fix Missing CRS result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Define paths
OUTPUT_FILE="/home/ga/GIS_Data/exports/sf_landmarks_wgs84.geojson"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 3. Check file existence and stats
FILE_EXISTS="false"
FILE_SIZE=0
IS_NEW="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        IS_NEW="true"
    fi
fi

# 4. Analyze content with Python
# We need to verify: 
# a) Valid GeoJSON
# b) CRS is WGS84
# c) Coordinates are actually in SF (checking logic: if raw values are > 1000, they didn't fix projection)

ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
import sys
import math

output_path = "/home/ga/GIS_Data/exports/sf_landmarks_wgs84.geojson"

result = {
    "valid_geojson": False,
    "crs_is_wgs84": False,
    "feature_count": 0,
    "first_feature_coords": None,
    "spatial_check_passed": False,
    "error": None
}

try:
    with open(output_path, 'r') as f:
        data = json.load(f)
    
    result["valid_geojson"] = True
    features = data.get("features", [])
    result["feature_count"] = len(features)
    
    # Check CRS
    # GeoJSON default is WGS84 (URN:OGC:DEF:CRS:OGC:1.3:CRS84) or no crs member
    crs = data.get("crs", {})
    if not crs:
        # No CRS object means WGS84 by default in GeoJSON spec
        result["crs_is_wgs84"] = True
    else:
        crs_name = crs.get("properties", {}).get("name", "").lower()
        if "crs84" in crs_name or "4326" in crs_name:
            result["crs_is_wgs84"] = True
    
    # Check Coordinates of first feature (Golden Gate Bridge)
    # Expected: [-122.4783, 37.8199]
    if features:
        geom = features[0].get("geometry", {})
        coords = geom.get("coordinates", [])
        if coords and len(coords) >= 2:
            lon, lat = coords[0], coords[1]
            result["first_feature_coords"] = [lon, lat]
            
            # Simple bounds check for SF
            # Lon: -122.6 to -122.3
            # Lat: 37.7 to 37.9
            if (-122.6 < lon < -122.3) and (37.7 < lat < 37.9):
                result["spatial_check_passed"] = True
            
            # Check for the common failure mode (raw state plane coords)
            # State plane coords would be like: 6,000,000 / 2,000,000
            if abs(lon) > 1000 or abs(lat) > 1000:
                result["error"] = "Coordinates appear to be raw State Plane values (unprojected)"

except FileNotFoundError:
    result["error"] = "File not found"
except json.JSONDecodeError:
    result["error"] = "Invalid JSON format"
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
)

# 5. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "is_new": $IS_NEW,
    "analysis": $ANALYSIS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
sudo mv "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="