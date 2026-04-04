#!/bin/bash
set -euo pipefail

echo "=== Exporting River Confluence Marking task result ==="

export DISPLAY=${DISPLAY:-:1}

# Capture final screenshot FIRST (before any other operations)
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    SCREENSHOT_EXISTS="true"
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
else
    SCREENSHOT_SIZE="0"
    SCREENSHOT_EXISTS="false"
    echo "WARNING: Could not capture final screenshot"
fi

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get initial state
INITIAL_MTIME=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('myplaces_mtime', 0))" 2>/dev/null || echo "0")
INITIAL_SIZE=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('myplaces_size', 0))" 2>/dev/null || echo "0")
INITIAL_EXISTS=$(python3 -c "import json; v=json.load(open('/tmp/initial_state.json')).get('myplaces_exists', False); print('true' if v else 'false')" 2>/dev/null || echo "false")

# Check current state of myplaces.kml
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"

if [ -f "$MYPLACES_PATH" ]; then
    CURRENT_EXISTS="true"
    CURRENT_MTIME=$(stat -c %Y "$MYPLACES_PATH" 2>/dev/null || echo "0")
    CURRENT_SIZE=$(stat -c %s "$MYPLACES_PATH" 2>/dev/null || echo "0")
    
    # Copy myplaces.kml to accessible location for verifier
    cp "$MYPLACES_PATH" /tmp/myplaces_final.kml 2>/dev/null || true
    chmod 644 /tmp/myplaces_final.kml 2>/dev/null || true
else
    CURRENT_EXISTS="false"
    CURRENT_MTIME="0"
    CURRENT_SIZE="0"
fi

# Determine if file was created or modified during task
FILE_CREATED="false"
FILE_MODIFIED="false"

if [ "$CURRENT_EXISTS" = "true" ]; then
    if [ "$INITIAL_EXISTS" = "false" ]; then
        FILE_CREATED="true"
    elif [ "$CURRENT_MTIME" != "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Check if Google Earth is still running
GE_RUNNING="false"
if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Get current window title
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")

# Extract placemark information from myplaces.kml
PLACEMARK_FOUND="false"
PLACEMARK_NAME=""
PLACEMARK_COORDS=""
PLACEMARK_DESCRIPTION=""

if [ -f /tmp/myplaces_final.kml ]; then
    # Use Python to parse KML and extract placemark info
    PLACEMARK_INFO=$(python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json
import re

result = {
    "found": False,
    "name": "",
    "coordinates": "",
    "description": "",
    "lat": 0,
    "lon": 0
}

try:
    tree = ET.parse('/tmp/myplaces_final.kml')
    root = tree.getroot()
    
    # Handle KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    # Search for placemarks (with or without namespace)
    for elem in root.iter():
        if 'Placemark' in elem.tag:
            name = ""
            coords = ""
            desc = ""
            
            for child in elem:
                tag = child.tag.lower()
                if '}' in tag:
                    tag = tag.split('}')[1]
                
                if tag == 'name' and child.text:
                    name = child.text.strip()
                elif tag == 'description' and child.text:
                    desc = child.text.strip()
                elif 'point' in tag.lower():
                    for subchild in child:
                        subtag = subchild.tag.lower()
                        if '}' in subtag:
                            subtag = subtag.split('}')[1]
                        if 'coordinates' in subtag and subchild.text:
                            coords = subchild.text.strip()
            
            # Check if this is our target placemark (case-insensitive)
            if name and 'ohio' in name.lower() and 'mississippi' in name.lower() and 'confluence' in name.lower():
                result["found"] = True
                result["name"] = name
                result["coordinates"] = coords
                result["description"] = desc
                
                # Parse coordinates (KML format: lon,lat,altitude)
                if coords:
                    parts = coords.split(',')
                    if len(parts) >= 2:
                        try:
                            result["lon"] = float(parts[0])
                            result["lat"] = float(parts[1])
                        except:
                            pass
                break

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
)
    
    if [ -n "$PLACEMARK_INFO" ]; then
        PLACEMARK_FOUND=$(echo "$PLACEMARK_INFO" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('found') else 'false')" 2>/dev/null || echo "false")
        PLACEMARK_NAME=$(echo "$PLACEMARK_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name', ''))" 2>/dev/null || echo "")
        PLACEMARK_COORDS=$(echo "$PLACEMARK_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('coordinates', ''))" 2>/dev/null || echo "")
        PLACEMARK_DESCRIPTION=$(echo "$PLACEMARK_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('description', ''))" 2>/dev/null || echo "")
        PLACEMARK_LAT=$(echo "$PLACEMARK_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('lat', 0))" 2>/dev/null || echo "0")
        PLACEMARK_LON=$(echo "$PLACEMARK_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('lon', 0))" 2>/dev/null || echo "0")
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "myplaces_exists": $CURRENT_EXISTS,
    "myplaces_mtime": $CURRENT_MTIME,
    "myplaces_size": $CURRENT_SIZE,
    "file_created": $FILE_CREATED,
    "file_modified": $FILE_MODIFIED,
    "google_earth_running": $GE_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final_state.png",
    "placemark_found": $PLACEMARK_FOUND,
    "placemark_name": "$PLACEMARK_NAME",
    "placemark_coordinates": "$PLACEMARK_COORDS",
    "placemark_description": "$PLACEMARK_DESCRIPTION",
    "placemark_lat": $PLACEMARK_LAT,
    "placemark_lon": $PLACEMARK_LON
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo ""