#!/bin/bash
set -e
echo "=== Exporting Scale Calibration Markers task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot BEFORE any other operations
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_evidence/task_final_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_evidence/task_final_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_evidence/task_final_screenshot.png ]; then
    SIZE=$(stat -c %s /tmp/task_evidence/task_final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Check myplaces.kml
MYPLACES="/home/ga/.googleearth/myplaces.kml"
MYPLACES_EXISTS="false"
MYPLACES_MTIME="0"
MYPLACES_SIZE="0"
FILE_MODIFIED_DURING_TASK="false"

if [ -f "$MYPLACES" ]; then
    MYPLACES_EXISTS="true"
    MYPLACES_MTIME=$(stat -c %Y "$MYPLACES" 2>/dev/null || echo "0")
    MYPLACES_SIZE=$(stat -c %s "$MYPLACES" 2>/dev/null || echo "0")
    
    # Check if modified during task
    if [ "$MYPLACES_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
        echo "myplaces.kml was modified during task"
    else
        echo "WARNING: myplaces.kml was NOT modified during task"
    fi
    
    # Copy the file for verification
    cp "$MYPLACES" /tmp/task_evidence/myplaces_final.kml 2>/dev/null || true
    echo "Copied myplaces.kml to evidence folder"
else
    echo "WARNING: myplaces.kml not found"
fi

# Check if Google Earth is still running
GE_RUNNING="false"
GE_WINDOW_TITLE=""
if pgrep -f "google-earth-pro" > /dev/null; then
    GE_RUNNING="true"
fi

# Get window title
GE_WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "unknown")

# Parse placemarks from KML if it exists
PLACEMARKS_JSON="[]"
if [ -f "$MYPLACES" ]; then
    PLACEMARKS_JSON=$(python3 << 'PYEOF'
import sys
import json
from xml.etree import ElementTree as ET

def parse_placemarks(filepath):
    placemarks = []
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Handle KML namespace
        ns = {'kml': 'http://www.opengis.net/kml/2.2'}
        
        # Try with namespace
        for pm in root.findall('.//kml:Placemark', ns):
            name_elem = pm.find('kml:name', ns)
            coords_elem = pm.find('.//kml:coordinates', ns)
            if name_elem is not None and coords_elem is not None:
                name = name_elem.text.strip() if name_elem.text else ""
                coords = coords_elem.text.strip().split(',')
                if len(coords) >= 2:
                    try:
                        lon, lat = float(coords[0]), float(coords[1])
                        placemarks.append({"name": name, "lat": lat, "lon": lon})
                    except ValueError:
                        pass
        
        # Try without namespace if nothing found
        if not placemarks:
            for pm in root.findall('.//Placemark'):
                name_elem = pm.find('name')
                coords_elem = pm.find('.//coordinates')
                if name_elem is not None and coords_elem is not None:
                    name = name_elem.text.strip() if name_elem.text else ""
                    coords = coords_elem.text.strip().split(',')
                    if len(coords) >= 2:
                        try:
                            lon, lat = float(coords[0]), float(coords[1])
                            placemarks.append({"name": name, "lat": lat, "lon": lon})
                        except ValueError:
                            pass
    except Exception as e:
        pass
    return placemarks

placemarks = parse_placemarks("/home/ga/.googleearth/myplaces.kml")
print(json.dumps(placemarks))
PYEOF
)
fi

echo "Parsed placemarks: $PLACEMARKS_JSON"

# Create the result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "myplaces_exists": $MYPLACES_EXISTS,
    "myplaces_mtime": $MYPLACES_MTIME,
    "myplaces_size_bytes": $MYPLACES_SIZE,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "google_earth_running": $GE_RUNNING,
    "window_title": "$GE_WINDOW_TITLE",
    "placemarks": $PLACEMARKS_JSON,
    "screenshot_final": "/tmp/task_evidence/task_final_screenshot.png",
    "screenshot_initial": "/tmp/task_evidence/task_initial_screenshot.png",
    "myplaces_final_path": "/tmp/task_evidence/myplaces_final.kml",
    "myplaces_initial_path": "/tmp/task_evidence/myplaces_initial.kml"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Task Result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="