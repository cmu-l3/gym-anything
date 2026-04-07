#!/bin/bash
set -e
echo "=== Exporting Antipodal Point Marking task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
else
    echo "WARNING: Could not capture final screenshot"
fi

# Check myplaces.kml
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"
MYPLACES_EXISTS="false"
MYPLACES_MODIFIED="false"
MYPLACES_SIZE="0"
MYPLACES_MTIME="0"
CURRENT_PLACEMARK_COUNT="0"
QUITO_ANTIPODE_EXISTS="false"
PLACEMARK_COORDINATES=""
PLACEMARK_LAT=""
PLACEMARK_LON=""

if [ -f "$MYPLACES_FILE" ]; then
    MYPLACES_EXISTS="true"
    MYPLACES_SIZE=$(stat -c %s "$MYPLACES_FILE" 2>/dev/null || echo "0")
    MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_FILE" 2>/dev/null || echo "0")
    CURRENT_PLACEMARK_COUNT=$(grep -c "<Placemark>" "$MYPLACES_FILE" 2>/dev/null || echo "0")
    
    # Check if modified during task
    INITIAL_MTIME=$(cat /tmp/initial_myplaces_mtime.txt 2>/dev/null || echo "0")
    if [ "$MYPLACES_MTIME" -gt "$INITIAL_MTIME" ] && [ "$MYPLACES_MTIME" -gt "$TASK_START" ]; then
        MYPLACES_MODIFIED="true"
    fi
    
    # Check for "Quito Antipode" placemark
    if grep -qi "Quito Antipode" "$MYPLACES_FILE" 2>/dev/null; then
        QUITO_ANTIPODE_EXISTS="true"
        
        # Extract coordinates using Python
        COORD_INFO=$(python3 << 'PYEOF'
import re
import json

try:
    with open("/home/ga/.googleearth/myplaces.kml", "r") as f:
        content = f.read()
    
    # Find Quito Antipode placemark
    pattern = r'<Placemark[^>]*>.*?<name>\s*Quito Antipode\s*</name>.*?<coordinates>\s*([^<]+)\s*</coordinates>.*?</Placemark>'
    match = re.search(pattern, content, re.DOTALL | re.IGNORECASE)
    
    if match:
        coords = match.group(1).strip()
        parts = coords.split(',')
        if len(parts) >= 2:
            lon = float(parts[0])
            lat = float(parts[1])
            print(json.dumps({"found": True, "lat": lat, "lon": lon, "raw": coords}))
        else:
            print(json.dumps({"found": False, "error": "Could not parse coordinates"}))
    else:
        print(json.dumps({"found": False, "error": "Placemark not found"}))
except Exception as e:
    print(json.dumps({"found": False, "error": str(e)}))
PYEOF
)
        
        COORD_FOUND=$(echo "$COORD_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('found', False))" 2>/dev/null || echo "False")
        if [ "$COORD_FOUND" = "True" ]; then
            PLACEMARK_LAT=$(echo "$COORD_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('lat', ''))" 2>/dev/null || echo "")
            PLACEMARK_LON=$(echo "$COORD_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('lon', ''))" 2>/dev/null || echo "")
            PLACEMARK_COORDINATES=$(echo "$COORD_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('raw', ''))" 2>/dev/null || echo "")
        fi
    fi
    
    # Copy myplaces.kml for verification
    cp "$MYPLACES_FILE" /tmp/myplaces_final.kml 2>/dev/null || true
    chmod 644 /tmp/myplaces_final.kml 2>/dev/null || true
fi

# Check if Google Earth is running
GE_RUNNING="false"
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Get window information
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")

# Get initial placemark count
INITIAL_PLACEMARK_COUNT=$(cat /tmp/initial_placemark_count.txt 2>/dev/null || echo "0")
PLACEMARK_COUNT_INCREASED="false"
if [ "$CURRENT_PLACEMARK_COUNT" -gt "$INITIAL_PLACEMARK_COUNT" ]; then
    PLACEMARK_COUNT_INCREASED="true"
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "myplaces_exists": $MYPLACES_EXISTS,
    "myplaces_modified_during_task": $MYPLACES_MODIFIED,
    "myplaces_size_bytes": $MYPLACES_SIZE,
    "myplaces_mtime": $MYPLACES_MTIME,
    "initial_placemark_count": $INITIAL_PLACEMARK_COUNT,
    "current_placemark_count": $CURRENT_PLACEMARK_COUNT,
    "placemark_count_increased": $PLACEMARK_COUNT_INCREASED,
    "quito_antipode_exists": $QUITO_ANTIPODE_EXISTS,
    "placemark_latitude": ${PLACEMARK_LAT:-null},
    "placemark_longitude": ${PLACEMARK_LON:-null},
    "placemark_coordinates_raw": "${PLACEMARK_COORDINATES}",
    "google_earth_running": $GE_RUNNING,
    "window_title": "${WINDOW_TITLE}",
    "screenshot_path": "/tmp/task_final_state.png",
    "myplaces_kml_path": "/tmp/myplaces_final.kml"
}
EOF

chmod 644 /tmp/task_result.json

echo ""
echo "=== Task Result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="