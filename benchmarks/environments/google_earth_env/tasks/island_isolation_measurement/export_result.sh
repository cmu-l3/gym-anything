#!/bin/bash
set -euo pipefail

echo "=== Exporting island_isolation_measurement task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task end time: $TASK_END"
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot BEFORE any other operations
echo "Capturing final state screenshot..."
scrot /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# ================================================================
# CHECK MYPLACES.KML FOR PATH DATA
# ================================================================

MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"
RESULT_FILE="/tmp/task_result.json"

# Initialize result variables
MYPLACES_EXISTS="false"
MYPLACES_MTIME="0"
MYPLACES_SIZE="0"
MYPLACES_HASH=""
FILE_MODIFIED_DURING_TASK="false"
PATH_COUNT="0"
PATHS_JSON="[]"
GOOGLE_EARTH_RUNNING="false"

# Check if Google Earth is still running
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GOOGLE_EARTH_RUNNING="true"
fi

# Check myplaces.kml
if [ -f "$MYPLACES_FILE" ]; then
    MYPLACES_EXISTS="true"
    MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_FILE" 2>/dev/null || echo "0")
    MYPLACES_SIZE=$(stat -c %s "$MYPLACES_FILE" 2>/dev/null || echo "0")
    MYPLACES_HASH=$(md5sum "$MYPLACES_FILE" 2>/dev/null | cut -d' ' -f1 || echo "")
    
    # Check if file was modified during task
    if [ "$MYPLACES_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
        echo "myplaces.kml was modified during task"
    else
        echo "myplaces.kml was NOT modified during task"
    fi
    
    # Count paths (LineString elements)
    PATH_COUNT=$(grep -c "<LineString>" "$MYPLACES_FILE" 2>/dev/null || echo "0")
    echo "Found $PATH_COUNT paths in myplaces.kml"
    
    # Copy myplaces.kml for analysis
    cp "$MYPLACES_FILE" /tmp/myplaces_final.kml 2>/dev/null || true
fi

# ================================================================
# EXTRACT PATH DATA USING PYTHON
# ================================================================

PATHS_JSON=$(python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json
import re
import math

def haversine(lat1, lon1, lat2, lon2):
    """Calculate distance in km between two points."""
    R = 6371
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    return R * 2 * math.asin(math.sqrt(a))

paths = []
try:
    kml_file = "/tmp/myplaces_final.kml"
    with open(kml_file, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
    
    # Remove namespace prefixes for easier parsing
    content = re.sub(r'xmlns[^"]*"[^"]*"', '', content)
    content = re.sub(r'<kml[^>]*>', '<kml>', content)
    
    root = ET.fromstring(content)
    
    for placemark in root.iter('Placemark'):
        name_elem = placemark.find('.//name')
        name = name_elem.text if name_elem is not None else "Unnamed"
        
        # Look for LineString (path/line measurements)
        linestring = placemark.find('.//LineString')
        if linestring is not None:
            coords_elem = linestring.find('.//coordinates')
            if coords_elem is not None and coords_elem.text:
                coord_text = coords_elem.text.strip()
                coord_pairs = []
                for coord in coord_text.split():
                    parts = coord.split(',')
                    if len(parts) >= 2:
                        lon, lat = float(parts[0]), float(parts[1])
                        coord_pairs.append({"lat": lat, "lon": lon})
                
                if len(coord_pairs) >= 2:
                    start = coord_pairs[0]
                    end = coord_pairs[-1]
                    distance = haversine(start["lat"], start["lon"], end["lat"], end["lon"])
                    
                    paths.append({
                        "name": name,
                        "start_lat": start["lat"],
                        "start_lon": start["lon"],
                        "end_lat": end["lat"],
                        "end_lon": end["lon"],
                        "distance_km": round(distance, 2),
                        "point_count": len(coord_pairs)
                    })
    
    print(json.dumps(paths))
except Exception as e:
    print(json.dumps([]))
PYEOF
)

echo "Extracted paths: $PATHS_JSON"

# ================================================================
# CHECK WINDOW STATE
# ================================================================

WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
GE_WINDOWS=$(wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")

# ================================================================
# LOAD INITIAL STATE FOR COMPARISON
# ================================================================

INITIAL_PATH_COUNT="0"
INITIAL_MYPLACES_HASH=""
if [ -f /tmp/initial_state.json ]; then
    INITIAL_PATH_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('path_count', 0))" 2>/dev/null || echo "0")
    INITIAL_MYPLACES_HASH=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('myplaces_hash', ''))" 2>/dev/null || echo "")
fi

# Calculate if new paths were added
NEW_PATHS_ADDED="false"
if [ "$PATH_COUNT" -gt "$INITIAL_PATH_COUNT" ]; then
    NEW_PATHS_ADDED="true"
fi

# Check if hash changed
HASH_CHANGED="false"
if [ -n "$MYPLACES_HASH" ] && [ "$MYPLACES_HASH" != "$INITIAL_MYPLACES_HASH" ]; then
    HASH_CHANGED="true"
fi

# ================================================================
# CREATE RESULT JSON
# ================================================================

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "myplaces_exists": $MYPLACES_EXISTS,
    "myplaces_mtime": $MYPLACES_MTIME,
    "myplaces_size": $MYPLACES_SIZE,
    "myplaces_hash": "$MYPLACES_HASH",
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "hash_changed": $HASH_CHANGED,
    "path_count": $PATH_COUNT,
    "initial_path_count": $INITIAL_PATH_COUNT,
    "new_paths_added": $NEW_PATHS_ADDED,
    "paths": $PATHS_JSON,
    "google_earth_running": $GOOGLE_EARTH_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "screenshot_final": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Task Result Summary ==="
cat "$RESULT_FILE"
echo ""
echo "=== Export complete ==="