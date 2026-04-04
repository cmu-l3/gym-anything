#!/bin/bash
set -euo pipefail

echo "=== Exporting glacier_terminus_width task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task start: $TASK_START, Task end: $TASK_END"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_final_screenshot.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
fi

# ================================================================
# Check output KML file
# ================================================================
OUTPUT_PATH="/home/ga/Documents/glacier_terminus.kml"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    echo "Output file found: $OUTPUT_PATH"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $OUTPUT_MTIME"
    echo "  Created during task: $FILE_CREATED_DURING_TASK"
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
    echo "Output file NOT found at $OUTPUT_PATH"
fi

# ================================================================
# Parse KML content if it exists
# ================================================================
KML_VALID="false"
PATH_FOUND="false"
PATH_NAME=""
PATH_COORDS=""
PATH_POINT_COUNT="0"
PLACEMARK_FOUND="false"
PLACEMARK_NAME=""
PLACEMARK_COORDS=""
PLACEMARK_DESCRIPTION=""

if [ "$OUTPUT_EXISTS" = "true" ] && [ "$OUTPUT_SIZE" -gt "100" ]; then
    echo ""
    echo "Parsing KML file..."
    
    # Extract KML content using Python
    KML_ANALYSIS=$(python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json
import re
import math

def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two points in km."""
    R = 6371  # Earth's radius in km
    lat1_r, lat2_r = math.radians(lat1), math.radians(lat2)
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2)**2 + math.cos(lat1_r) * math.cos(lat2_r) * math.sin(dlon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

def calculate_path_length(coords_str):
    """Calculate total path length from coordinate string."""
    coords = []
    for part in coords_str.strip().split():
        try:
            lon, lat, *_ = part.split(',')
            coords.append((float(lat), float(lon)))
        except:
            continue
    
    if len(coords) < 2:
        return 0, []
    
    total_dist = 0
    for i in range(len(coords) - 1):
        dist = haversine_distance(coords[i][0], coords[i][1], 
                                   coords[i+1][0], coords[i+1][1])
        total_dist += dist
    
    return total_dist, coords

result = {
    "kml_valid": False,
    "path_found": False,
    "path_name": "",
    "path_coords": "",
    "path_point_count": 0,
    "path_length_km": 0,
    "path_lat_min": 0,
    "path_lat_max": 0,
    "path_lon_min": 0,
    "path_lon_max": 0,
    "placemark_found": False,
    "placemark_name": "",
    "placemark_coords": "",
    "placemark_lat": 0,
    "placemark_lon": 0,
    "placemark_description": "",
    "measurement_in_description": False,
    "measurement_value_km": 0
}

try:
    tree = ET.parse("/home/ga/Documents/glacier_terminus.kml")
    root = tree.getroot()
    result["kml_valid"] = True
    
    # Handle KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    # Find all Placemarks (both with and without namespace)
    placemarks = root.findall('.//kml:Placemark', ns)
    if not placemarks:
        placemarks = root.findall('.//Placemark')
    
    for pm in placemarks:
        # Get name
        name_elem = pm.find('kml:name', ns) or pm.find('name')
        name = name_elem.text if name_elem is not None else ""
        
        # Check for LineString (Path)
        linestring = pm.find('.//kml:LineString', ns) or pm.find('.//LineString')
        if linestring is not None:
            coords_elem = linestring.find('kml:coordinates', ns) or linestring.find('coordinates')
            if coords_elem is not None and coords_elem.text:
                result["path_found"] = True
                result["path_name"] = name
                result["path_coords"] = coords_elem.text.strip()[:500]  # Limit size
                
                length, coords = calculate_path_length(coords_elem.text)
                result["path_length_km"] = round(length, 2)
                result["path_point_count"] = len(coords)
                
                if coords:
                    lats = [c[0] for c in coords]
                    lons = [c[1] for c in coords]
                    result["path_lat_min"] = min(lats)
                    result["path_lat_max"] = max(lats)
                    result["path_lon_min"] = min(lons)
                    result["path_lon_max"] = max(lons)
        
        # Check for Point (Placemark)
        point = pm.find('.//kml:Point', ns) or pm.find('.//Point')
        if point is not None:
            coords_elem = point.find('kml:coordinates', ns) or point.find('coordinates')
            if coords_elem is not None and coords_elem.text:
                result["placemark_found"] = True
                result["placemark_name"] = name
                result["placemark_coords"] = coords_elem.text.strip()
                
                try:
                    lon, lat, *_ = coords_elem.text.strip().split(',')
                    result["placemark_lat"] = float(lat)
                    result["placemark_lon"] = float(lon)
                except:
                    pass
                
                # Get description
                desc_elem = pm.find('kml:description', ns) or pm.find('description')
                if desc_elem is not None and desc_elem.text:
                    result["placemark_description"] = desc_elem.text[:200]
                    
                    # Look for measurement value
                    match = re.search(r'(\d+\.?\d*)\s*(km|kilometer)', desc_elem.text, re.I)
                    if match:
                        result["measurement_in_description"] = True
                        result["measurement_value_km"] = float(match.group(1))

    print(json.dumps(result))

except Exception as e:
    result["error"] = str(e)
    print(json.dumps(result))
PYEOF
)
    
    echo "KML Analysis: $KML_ANALYSIS"
    
    # Extract values from analysis
    KML_VALID=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('kml_valid', False)).lower())")
    PATH_FOUND=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('path_found', False)).lower())")
    PATH_NAME=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('path_name', ''))")
    PATH_POINT_COUNT=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('path_point_count', 0))")
    PATH_LENGTH_KM=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('path_length_km', 0))")
    PATH_LAT_MIN=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('path_lat_min', 0))")
    PATH_LAT_MAX=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('path_lat_max', 0))")
    PATH_LON_MIN=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('path_lon_min', 0))")
    PATH_LON_MAX=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('path_lon_max', 0))")
    PLACEMARK_FOUND=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('placemark_found', False)).lower())")
    PLACEMARK_NAME=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('placemark_name', ''))")
    PLACEMARK_LAT=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('placemark_lat', 0))")
    PLACEMARK_LON=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('placemark_lon', 0))")
    PLACEMARK_DESC=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('placemark_description', ''))")
    MEASUREMENT_IN_DESC=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('measurement_in_description', False)).lower())")
    MEASUREMENT_VALUE=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('measurement_value_km', 0))")
fi

# ================================================================
# Check Google Earth state
# ================================================================
GE_RUNNING="false"
if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

GE_WINDOW=""
if wmctrl -l 2>/dev/null | grep -qi "Google Earth"; then
    GE_WINDOW=$(wmctrl -l | grep -i "Google Earth" | head -1)
fi

# ================================================================
# Create result JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "kml_valid": $KML_VALID,
    "path_found": $PATH_FOUND,
    "path_name": "$PATH_NAME",
    "path_point_count": $PATH_POINT_COUNT,
    "path_length_km": ${PATH_LENGTH_KM:-0},
    "path_lat_min": ${PATH_LAT_MIN:-0},
    "path_lat_max": ${PATH_LAT_MAX:-0},
    "path_lon_min": ${PATH_LON_MIN:-0},
    "path_lon_max": ${PATH_LON_MAX:-0},
    "placemark_found": $PLACEMARK_FOUND,
    "placemark_name": "$PLACEMARK_NAME",
    "placemark_lat": ${PLACEMARK_LAT:-0},
    "placemark_lon": ${PLACEMARK_LON:-0},
    "placemark_description": "$PLACEMARK_DESC",
    "measurement_in_description": $MEASUREMENT_IN_DESC,
    "measurement_value_km": ${MEASUREMENT_VALUE:-0},
    "google_earth_running": $GE_RUNNING,
    "google_earth_window": "$GE_WINDOW",
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# Copy to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json