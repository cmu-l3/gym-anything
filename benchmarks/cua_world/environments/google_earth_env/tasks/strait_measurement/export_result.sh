#!/bin/bash
set -e
echo "=== Exporting Strait Measurement Task Result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final state..."
scrot /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Check myplaces.kml status
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
MYPLACES_EXISTS="false"
MYPLACES_MODIFIED="false"
MYPLACES_MTIME="0"
MYPLACES_SIZE="0"
NEW_PATH_COUNT="0"
PATHS_ADDED="0"

if [ -f "$MYPLACES_PATH" ]; then
    MYPLACES_EXISTS="true"
    MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_PATH" 2>/dev/null || echo "0")
    MYPLACES_SIZE=$(stat -c %s "$MYPLACES_PATH" 2>/dev/null || echo "0")
    
    # Check if modified during task
    ORIGINAL_MTIME=$(cat /tmp/myplaces_original_mtime.txt 2>/dev/null || echo "0")
    if [ "$MYPLACES_MTIME" -gt "$ORIGINAL_MTIME" ] && [ "$MYPLACES_MTIME" -ge "$TASK_START" ]; then
        MYPLACES_MODIFIED="true"
    fi
    
    # Count LineStrings (paths/measurements)
    NEW_PATH_COUNT=$(grep -c "<LineString>" "$MYPLACES_PATH" 2>/dev/null || echo "0")
    INITIAL_PATH_COUNT=$(cat /tmp/initial_path_count.txt 2>/dev/null || echo "0")
    PATHS_ADDED=$((NEW_PATH_COUNT - INITIAL_PATH_COUNT))
    
    echo "myplaces.kml found:"
    echo "  Size: $MYPLACES_SIZE bytes"
    echo "  Modified time: $MYPLACES_MTIME"
    echo "  Modified during task: $MYPLACES_MODIFIED"
    echo "  LineString count: $NEW_PATH_COUNT (was $INITIAL_PATH_COUNT)"
    echo "  Paths added: $PATHS_ADDED"
fi

# Extract path data from myplaces.kml
PATHS_DATA="[]"
if [ -f "$MYPLACES_PATH" ] && [ "$MYPLACES_EXISTS" = "true" ]; then
    # Use Python to parse KML and extract path information
    PATHS_DATA=$(python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json
import re

def parse_coordinates(coord_string):
    """Parse KML coordinate string into list of (lon, lat) tuples."""
    coords = []
    for point in coord_string.strip().split():
        parts = point.split(',')
        if len(parts) >= 2:
            try:
                lon, lat = float(parts[0]), float(parts[1])
                coords.append({"lon": lon, "lat": lat})
            except ValueError:
                continue
    return coords

paths = []
try:
    tree = ET.parse("/home/ga/.googleearth/myplaces.kml")
    root = tree.getroot()
    
    # KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    # Find all elements (handle namespace issues)
    for elem in root.iter():
        if 'Placemark' in elem.tag:
            name = ""
            coordinates = []
            
            # Find name
            for child in elem.iter():
                if 'name' in child.tag and child.text:
                    name = child.text.strip()
                elif 'coordinates' in child.tag and child.text:
                    # Check if parent is LineString
                    parent = None
                    for p in elem.iter():
                        if 'LineString' in p.tag:
                            for c in p.iter():
                                if 'coordinates' in c.tag and c.text:
                                    coordinates = parse_coordinates(c.text)
                                    break
                            break
                    if not coordinates:
                        coordinates = parse_coordinates(child.text)
            
            if coordinates and len(coordinates) >= 2:
                paths.append({
                    "name": name,
                    "coordinates": coordinates,
                    "num_points": len(coordinates)
                })

except Exception as e:
    print(json.dumps([]))
    exit(0)

print(json.dumps(paths))
PYEOF
)
fi

# Check if Google Earth is still running
GE_RUNNING="false"
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Check for Ruler window (might still be visible)
RULER_VISIBLE="false"
if wmctrl -l 2>/dev/null | grep -qi "ruler"; then
    RULER_VISIBLE="true"
fi

# Record window state
wmctrl -l > /tmp/final_windows.txt 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "myplaces_exists": $MYPLACES_EXISTS,
    "myplaces_modified": $MYPLACES_MODIFIED,
    "myplaces_mtime": $MYPLACES_MTIME,
    "myplaces_size_bytes": $MYPLACES_SIZE,
    "initial_path_count": $(cat /tmp/initial_path_count.txt 2>/dev/null || echo "0"),
    "final_path_count": $NEW_PATH_COUNT,
    "paths_added": $PATHS_ADDED,
    "paths_data": $PATHS_DATA,
    "google_earth_running": $GE_RUNNING,
    "ruler_visible": $RULER_VISIBLE,
    "final_screenshot_path": "/tmp/task_final_state.png",
    "initial_screenshot_path": "/tmp/task_initial_state.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON:"
cat /tmp/task_result.json
echo ""

# Also copy the myplaces.kml for analysis
if [ -f "$MYPLACES_PATH" ]; then
    cp "$MYPLACES_PATH" /tmp/myplaces_final.kml 2>/dev/null || true
    chmod 666 /tmp/myplaces_final.kml 2>/dev/null || true
fi

echo "=== Export Complete ==="