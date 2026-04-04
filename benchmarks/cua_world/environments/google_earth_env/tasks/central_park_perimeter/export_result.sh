#!/bin/bash
set -e
echo "=== Exporting Central Park Perimeter task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot FIRST (before any state changes)
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
else
    FINAL_SCREENSHOT_SIZE="0"
    echo "WARNING: Could not capture final screenshot"
fi

# Check myplaces.kml file
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"
MYPLACES_EXISTS="false"
MYPLACES_SIZE="0"
MYPLACES_MTIME="0"
PATH_COUNT="0"
TARGET_PATH_FOUND="false"
COORDINATES_RAW=""
NUM_COORDINATES="0"

if [ -f "$MYPLACES_FILE" ]; then
    MYPLACES_EXISTS="true"
    MYPLACES_SIZE=$(stat -c %s "$MYPLACES_FILE" 2>/dev/null || echo "0")
    MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_FILE" 2>/dev/null || echo "0")
    
    # Count LineString elements (paths)
    PATH_COUNT=$(grep -c "<LineString>" "$MYPLACES_FILE" 2>/dev/null || echo "0")
    
    # Check for target path name (case-insensitive)
    if grep -qi "Central_Park_Perimeter\|Central Park Perimeter\|CentralParkPerimeter" "$MYPLACES_FILE" 2>/dev/null; then
        TARGET_PATH_FOUND="true"
        echo "Target path 'Central_Park_Perimeter' found in myplaces.kml"
    fi
    
    # Extract coordinates from the target path (simplified extraction)
    # This extracts raw coordinate data for the verifier to process
    COORDINATES_RAW=$(python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import sys
import re

try:
    tree = ET.parse("/home/ga/.googleearth/myplaces.kml")
    root = tree.getroot()
    
    # Handle KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    # Find placemarks with LineString
    for elem in root.iter():
        if elem.tag.endswith('Placemark'):
            name_elem = None
            coords_elem = None
            
            for child in elem.iter():
                if child.tag.endswith('name'):
                    name_elem = child
                if child.tag.endswith('coordinates'):
                    coords_elem = child
            
            if name_elem is not None and coords_elem is not None:
                name = name_elem.text or ""
                if 'central' in name.lower() and 'park' in name.lower() and 'perimeter' in name.lower():
                    coords = coords_elem.text.strip() if coords_elem.text else ""
                    print(coords)
                    sys.exit(0)
    
    print("")
except Exception as e:
    print("")
PYEOF
)
    
    # Count coordinates if found
    if [ -n "$COORDINATES_RAW" ]; then
        NUM_COORDINATES=$(echo "$COORDINATES_RAW" | tr ' ' '\n' | grep -c ',' || echo "0")
    fi
    
    echo "Path count: $PATH_COUNT"
    echo "Number of coordinates in target path: $NUM_COORDINATES"
fi

# Get initial state for comparison
INITIAL_PATH_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('initial_path_count', 0))" 2>/dev/null || echo "0")
INITIAL_MTIME=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('initial_mtime', 0))" 2>/dev/null || echo "0")

# Determine if file was created/modified during task
FILE_CREATED="false"
FILE_MODIFIED="false"

if [ "$MYPLACES_EXISTS" = "true" ]; then
    if [ "$MYPLACES_MTIME" -gt "$TASK_START" ]; then
        if [ "$INITIAL_MTIME" = "0" ] || [ "$INITIAL_MTIME" = "" ]; then
            FILE_CREATED="true"
        else
            FILE_MODIFIED="true"
        fi
    fi
fi

# Check if Google Earth is still running
GE_RUNNING="false"
GE_WINDOW_TITLE=""
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")
fi

# Copy myplaces.kml to tmp for verifier access
if [ -f "$MYPLACES_FILE" ]; then
    cp "$MYPLACES_FILE" /tmp/myplaces_export.kml 2>/dev/null || true
    chmod 644 /tmp/myplaces_export.kml 2>/dev/null || true
fi

# Create comprehensive result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "myplaces_exists": $MYPLACES_EXISTS,
    "myplaces_size_bytes": $MYPLACES_SIZE,
    "myplaces_mtime": $MYPLACES_MTIME,
    "file_created_during_task": $FILE_CREATED,
    "file_modified_during_task": $FILE_MODIFIED,
    "path_count": $PATH_COUNT,
    "initial_path_count": $INITIAL_PATH_COUNT,
    "target_path_found": $TARGET_PATH_FOUND,
    "num_coordinates": $NUM_COORDINATES,
    "coordinates_raw": "$COORDINATES_RAW",
    "google_earth_running": $GE_RUNNING,
    "window_title": "$GE_WINDOW_TITLE",
    "final_screenshot_path": "/tmp/task_final.png",
    "final_screenshot_size": $FINAL_SCREENSHOT_SIZE,
    "myplaces_export_path": "/tmp/myplaces_export.kml"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="