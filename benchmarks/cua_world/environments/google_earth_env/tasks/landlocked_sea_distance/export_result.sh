#!/bin/bash
set -e
echo "=== Exporting Landlocked Sea Distance Task Result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_final_screenshot.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
else
    FINAL_SCREENSHOT_SIZE="0"
    echo "WARNING: Could not capture final screenshot"
fi

# ================================================================
# CHECK OUTPUT SCREENSHOT
# ================================================================
SCREENSHOT_PATH="/home/ga/Documents/distance_measurement.png"

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    SCREENSHOT_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    else
        SCREENSHOT_CREATED_DURING_TASK="false"
    fi
else
    SCREENSHOT_EXISTS="false"
    SCREENSHOT_SIZE="0"
    SCREENSHOT_MTIME="0"
    SCREENSHOT_CREATED_DURING_TASK="false"
fi

echo "Screenshot exists: $SCREENSHOT_EXISTS"
echo "Screenshot created during task: $SCREENSHOT_CREATED_DURING_TASK"

# ================================================================
# CHECK MYPLACES.KML FOR SAVED MEASUREMENT
# ================================================================
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"
MEASUREMENT_FOUND="false"
MEASUREMENT_NAME=""
COORDINATES_DATA=""

if [ -f "$MYPLACES_FILE" ]; then
    MYPLACES_EXISTS="true"
    MYPLACES_SIZE=$(stat -c %s "$MYPLACES_FILE" 2>/dev/null || echo "0")
    MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_FILE" 2>/dev/null || echo "0")
    
    # Check if modified during task
    INITIAL_MTIME=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('myplaces_mtime', 0))" 2>/dev/null || echo "0")
    if [ "$MYPLACES_MTIME" -gt "$INITIAL_MTIME" ]; then
        MYPLACES_MODIFIED="true"
    else
        MYPLACES_MODIFIED="false"
    fi
    
    # Search for measurement with expected name
    if grep -qi "Ulaanbaatar" "$MYPLACES_FILE" 2>/dev/null; then
        MEASUREMENT_FOUND="true"
        echo "Found reference to Ulaanbaatar in myplaces.kml"
    fi
    
    if grep -qi "Coast" "$MYPLACES_FILE" 2>/dev/null; then
        MEASUREMENT_FOUND="true"
        echo "Found reference to Coast in myplaces.kml"
    fi
    
    # Extract coordinates from LineString elements (ruler measurements)
    COORDINATES_DATA=$(python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json
import re

try:
    tree = ET.parse("/home/ga/.googleearth/myplaces.kml")
    root = tree.getroot()
    
    # Handle KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    results = []
    
    # Find all placemarks
    for elem in root.iter():
        if 'Placemark' in elem.tag:
            name = ""
            coords = []
            
            for child in elem.iter():
                if 'name' in child.tag.lower() and child.text:
                    name = child.text
                if 'coordinates' in child.tag.lower() and child.text:
                    coord_text = child.text.strip()
                    # Parse lon,lat,alt format
                    for coord in coord_text.split():
                        parts = coord.split(',')
                        if len(parts) >= 2:
                            try:
                                lon, lat = float(parts[0]), float(parts[1])
                                coords.append({"lat": lat, "lon": lon})
                            except:
                                pass
            
            if coords and len(coords) >= 2:
                results.append({
                    "name": name,
                    "coordinates": coords,
                    "num_points": len(coords)
                })
    
    print(json.dumps(results))
except Exception as e:
    print(json.dumps([]))
PYEOF
)
else
    MYPLACES_EXISTS="false"
    MYPLACES_SIZE="0"
    MYPLACES_MTIME="0"
    MYPLACES_MODIFIED="false"
fi

echo "myplaces.kml exists: $MYPLACES_EXISTS"
echo "myplaces.kml modified: $MYPLACES_MODIFIED"

# ================================================================
# CHECK FOR EXPORTED KML FILES
# ================================================================
EXPORTED_KML_FOUND="false"
EXPORTED_KML_PATH=""

for kml_file in /home/ga/Documents/*.kml /home/ga/Documents/*.kmz /home/ga/*.kml /home/ga/*.kmz; do
    if [ -f "$kml_file" ]; then
        EXPORTED_KML_FOUND="true"
        EXPORTED_KML_PATH="$kml_file"
        echo "Found exported KML: $kml_file"
        break
    fi
done

# ================================================================
# CHECK IF GOOGLE EARTH IS RUNNING
# ================================================================
if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f "google-earth-pro" | head -1)
else
    GE_RUNNING="false"
    GE_PID=""
fi

# Check window title
GE_WINDOW_TITLE=""
if wmctrl -l | grep -qi "Google Earth"; then
    GE_WINDOW_TITLE=$(wmctrl -l | grep -i "Google Earth" | head -1 | cut -d' ' -f5-)
fi

echo "Google Earth running: $GE_RUNNING"

# ================================================================
# CREATE RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "screenshot": {
        "exists": $SCREENSHOT_EXISTS,
        "path": "$SCREENSHOT_PATH",
        "size_bytes": $SCREENSHOT_SIZE,
        "mtime": $SCREENSHOT_MTIME,
        "created_during_task": $SCREENSHOT_CREATED_DURING_TASK
    },
    "myplaces": {
        "exists": $MYPLACES_EXISTS,
        "size_bytes": $MYPLACES_SIZE,
        "mtime": $MYPLACES_MTIME,
        "modified_during_task": $MYPLACES_MODIFIED,
        "measurement_found": $MEASUREMENT_FOUND
    },
    "coordinates_data": $COORDINATES_DATA,
    "exported_kml": {
        "found": $EXPORTED_KML_FOUND,
        "path": "$EXPORTED_KML_PATH"
    },
    "google_earth": {
        "running": $GE_RUNNING,
        "pid": "$GE_PID",
        "window_title": "$GE_WINDOW_TITLE"
    },
    "final_screenshot_path": "/tmp/task_final_screenshot.png",
    "final_screenshot_size": $FINAL_SCREENSHOT_SIZE
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="