#!/bin/bash
set -e
echo "=== Exporting Summit Identification Denali Result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot FIRST (before any other operations)
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
    SCREENSHOT_SIZE="0"
fi

# Check myplaces.kml
MYPLACES="/home/ga/.googleearth/myplaces.kml"
MYPLACES_ALT="/home/ga/.googleearth/default/myplaces.kml"

KML_PATH=""
if [ -f "$MYPLACES" ]; then
    KML_PATH="$MYPLACES"
elif [ -f "$MYPLACES_ALT" ]; then
    KML_PATH="$MYPLACES_ALT"
fi

if [ -n "$KML_PATH" ] && [ -f "$KML_PATH" ]; then
    KML_EXISTS="true"
    KML_SIZE=$(stat -c %s "$KML_PATH" 2>/dev/null || echo "0")
    KML_MTIME=$(stat -c %Y "$KML_PATH" 2>/dev/null || echo "0")
    
    # Check if file was modified during task
    if [ "$KML_MTIME" -gt "$TASK_START" ]; then
        KML_MODIFIED_DURING_TASK="true"
    else
        KML_MODIFIED_DURING_TASK="false"
    fi
    
    # Copy KML file to accessible location
    cp "$KML_PATH" /tmp/myplaces_export.kml 2>/dev/null || true
    chmod 644 /tmp/myplaces_export.kml 2>/dev/null || true
else
    KML_EXISTS="false"
    KML_SIZE="0"
    KML_MTIME="0"
    KML_MODIFIED_DURING_TASK="false"
fi

# Check if Google Earth is still running
GE_RUNNING=$(pgrep -f "google-earth" > /dev/null && echo "true" || echo "false")

# Get window info
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")

# Parse KML for Denali placemark details
PLACEMARK_FOUND="false"
PLACEMARK_NAME=""
PLACEMARK_LAT="0"
PLACEMARK_LON="0"
PLACEMARK_DESC=""

if [ -f /tmp/myplaces_export.kml ]; then
    # Extract placemark details using Python
    python3 << 'PYEOF' > /tmp/placemark_details.json 2>/dev/null || echo '{"found": false}' > /tmp/placemark_details.json
import xml.etree.ElementTree as ET
import json
import re

result = {
    "found": False,
    "name": "",
    "lat": 0,
    "lon": 0,
    "description": "",
    "raw_coordinates": ""
}

try:
    tree = ET.parse('/tmp/myplaces_export.kml')
    root = tree.getroot()
    
    # Search for Denali/Summit placemark
    for placemark in root.iter('{http://www.opengis.net/kml/2.2}Placemark'):
        name_elem = placemark.find('{http://www.opengis.net/kml/2.2}name')
        if name_elem is not None and name_elem.text:
            name_lower = name_elem.text.lower()
            if 'denali' in name_lower or 'summit' in name_lower:
                result["found"] = True
                result["name"] = name_elem.text
                
                # Get description
                desc_elem = placemark.find('{http://www.opengis.net/kml/2.2}description')
                if desc_elem is not None and desc_elem.text:
                    result["description"] = desc_elem.text
                
                # Get coordinates (format: lon,lat,alt)
                coords_elem = placemark.find('.//{http://www.opengis.net/kml/2.2}coordinates')
                if coords_elem is not None and coords_elem.text:
                    coords_text = coords_elem.text.strip()
                    result["raw_coordinates"] = coords_text
                    parts = coords_text.split(',')
                    if len(parts) >= 2:
                        result["lon"] = float(parts[0])
                        result["lat"] = float(parts[1])
                
                break
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
    
    if [ -f /tmp/placemark_details.json ]; then
        PLACEMARK_FOUND=$(python3 -c "import json; d=json.load(open('/tmp/placemark_details.json')); print('true' if d.get('found') else 'false')" 2>/dev/null || echo "false")
        PLACEMARK_NAME=$(python3 -c "import json; print(json.load(open('/tmp/placemark_details.json')).get('name', ''))" 2>/dev/null || echo "")
        PLACEMARK_LAT=$(python3 -c "import json; print(json.load(open('/tmp/placemark_details.json')).get('lat', 0))" 2>/dev/null || echo "0")
        PLACEMARK_LON=$(python3 -c "import json; print(json.load(open('/tmp/placemark_details.json')).get('lon', 0))" 2>/dev/null || echo "0")
        PLACEMARK_DESC=$(python3 -c "import json; print(json.load(open('/tmp/placemark_details.json')).get('description', '')[:500])" 2>/dev/null || echo "")
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_sec": $((TASK_END - TASK_START)),
    "kml_exists": $KML_EXISTS,
    "kml_size_bytes": $KML_SIZE,
    "kml_mtime": $KML_MTIME,
    "kml_modified_during_task": $KML_MODIFIED_DURING_TASK,
    "google_earth_running": $GE_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_bytes": $SCREENSHOT_SIZE,
    "placemark_found": $PLACEMARK_FOUND,
    "placemark_name": "$PLACEMARK_NAME",
    "placemark_lat": $PLACEMARK_LAT,
    "placemark_lon": $PLACEMARK_LON,
    "placemark_description": $(python3 -c "import json; print(json.dumps('$PLACEMARK_DESC'))" 2>/dev/null || echo '""')
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="