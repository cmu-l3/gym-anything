#!/bin/bash
echo "=== Exporting Metric Canal Measurement task result ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task end time: $TASK_END"
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot FIRST (before any state changes)
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
fi

# ================================================================
# Check myplaces.kml for saved measurement
# ================================================================
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
MYPLACES_EXISTS="false"
MYPLACES_MODIFIED="false"
MYPLACES_SIZE="0"
MYPLACES_MTIME="0"
MEASUREMENT_FOUND="false"
MEASUREMENT_NAME=""
MEASUREMENT_COORDS=""

if [ -f "$MYPLACES_PATH" ]; then
    MYPLACES_EXISTS="true"
    MYPLACES_SIZE=$(stat -c %s "$MYPLACES_PATH" 2>/dev/null || echo "0")
    MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_PATH" 2>/dev/null || echo "0")
    
    # Check if modified during task
    INITIAL_MTIME=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('myplaces_mtime', 0))" 2>/dev/null || echo "0")
    if [ "$MYPLACES_MTIME" -gt "$INITIAL_MTIME" ] && [ "$MYPLACES_MTIME" -gt "$TASK_START" ]; then
        MYPLACES_MODIFIED="true"
    fi
    
    # Search for the measurement placemark
    if grep -qi "Suez_Canal_Width_Metric" "$MYPLACES_PATH" 2>/dev/null; then
        MEASUREMENT_FOUND="true"
        MEASUREMENT_NAME="Suez_Canal_Width_Metric"
        
        # Extract coordinates from the placemark (simplified extraction)
        MEASUREMENT_COORDS=$(python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import re

try:
    tree = ET.parse("/home/ga/.googleearth/myplaces.kml")
    root = tree.getroot()
    
    # Handle KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    # Find all placemarks
    for elem in root.iter():
        if 'Placemark' in elem.tag:
            name_elem = None
            coords_elem = None
            for child in elem.iter():
                if 'name' in child.tag and child.text:
                    if 'Suez_Canal_Width_Metric' in child.text:
                        name_elem = child
                if 'coordinates' in child.tag and child.text:
                    coords_elem = child
            if name_elem is not None and coords_elem is not None:
                print(coords_elem.text.strip().replace('\n', ' ').replace('\t', ' '))
                break
except Exception as e:
    print("")
PYEOF
)
    fi
    
    # Copy myplaces.kml for verification
    cp "$MYPLACES_PATH" /tmp/myplaces_final.kml 2>/dev/null || true
fi

# ================================================================
# Check Google Earth configuration for metric units
# ================================================================
CONFIG_PATH="/home/ga/.config/Google/GoogleEarthPro.conf"
ALT_CONFIG_PATH="/home/ga/.googleearth/GoogleEarth.conf"
UNITS_METRIC="false"
CONFIG_EXISTS="false"
CONFIG_MODIFIED="false"
CONFIG_CONTENT=""

for CFG in "$CONFIG_PATH" "$ALT_CONFIG_PATH"; do
    if [ -f "$CFG" ]; then
        CONFIG_EXISTS="true"
        CONFIG_MTIME=$(stat -c %Y "$CFG" 2>/dev/null || echo "0")
        
        # Check if modified during task
        if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
            CONFIG_MODIFIED="true"
        fi
        
        # Read config content
        CONFIG_CONTENT=$(cat "$CFG" 2>/dev/null || echo "")
        
        # Check for metric units setting
        # Google Earth uses various config formats
        if echo "$CONFIG_CONTENT" | grep -qi "meter\|metric\|UnitsOfMeasure.*1"; then
            UNITS_METRIC="true"
        fi
        
        # Copy config for verification
        cp "$CFG" /tmp/googleearth_config_final.conf 2>/dev/null || true
        break
    fi
done

# ================================================================
# Check if Google Earth is still running
# ================================================================
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f google-earth-pro | head -1)
else
    GE_RUNNING="false"
    GE_PID=""
fi

# Get window title
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")

# ================================================================
# Create comprehensive result JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "google_earth_running": $GE_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "myplaces": {
        "exists": $MYPLACES_EXISTS,
        "modified_during_task": $MYPLACES_MODIFIED,
        "size_bytes": $MYPLACES_SIZE,
        "mtime": $MYPLACES_MTIME
    },
    "measurement": {
        "found": $MEASUREMENT_FOUND,
        "name": "$MEASUREMENT_NAME",
        "coordinates": "$MEASUREMENT_COORDS"
    },
    "config": {
        "exists": $CONFIG_EXISTS,
        "modified_during_task": $CONFIG_MODIFIED,
        "units_metric": $UNITS_METRIC
    }
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Task Result Summary ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="