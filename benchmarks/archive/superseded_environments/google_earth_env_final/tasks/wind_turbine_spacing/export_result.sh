#!/bin/bash
set -euo pipefail

echo "=== Exporting Wind Turbine Spacing task result ==="

export DISPLAY=${DISPLAY:-:1}

# ============================================================
# Record task end time
# ============================================================
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# ============================================================
# Take final screenshot BEFORE any other operations
# ============================================================
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

FINAL_SCREENSHOT_EXISTS="false"
FINAL_SCREENSHOT_SIZE="0"
if [ -f /tmp/task_final.png ]; then
    FINAL_SCREENSHOT_EXISTS="true"
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
fi

# ============================================================
# Check output screenshot
# ============================================================
OUTPUT_PATH="/home/ga/wind_farm_analysis.png"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "Output screenshot was created during task"
    else
        echo "WARNING: Output screenshot predates task start"
    fi
    echo "Output file size: ${OUTPUT_SIZE} bytes"
else
    echo "Output screenshot not found at $OUTPUT_PATH"
fi

# ============================================================
# Check My Places KML for placemarks
# ============================================================
MYPLACES_KML="/home/ga/.googleearth/myplaces.kml"
MYPLACES_MODIFIED="false"
CURRENT_PLACEMARK_COUNT="0"
TURBINE_PLACEMARKS_FOUND="0"
PLACEMARK_DATA=""

# Get initial state
INITIAL_PLACEMARK_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('initial_placemark_count', 0))" 2>/dev/null || echo "0")
INITIAL_MYPLACES_MTIME=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('initial_myplaces_mtime', 0))" 2>/dev/null || echo "0")

if [ -f "$MYPLACES_KML" ]; then
    CURRENT_MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_KML" 2>/dev/null || echo "0")
    
    if [ "$CURRENT_MYPLACES_MTIME" -gt "$INITIAL_MYPLACES_MTIME" ]; then
        MYPLACES_MODIFIED="true"
        echo "My Places was modified during task"
    fi
    
    CURRENT_PLACEMARK_COUNT=$(grep -c "<Placemark>" "$MYPLACES_KML" 2>/dev/null || echo "0")
    echo "Current placemark count: $CURRENT_PLACEMARK_COUNT (was: $INITIAL_PLACEMARK_COUNT)"
    
    # Extract turbine-related placemarks
    TURBINE_PLACEMARKS_FOUND=$(grep -i "turbine" "$MYPLACES_KML" 2>/dev/null | grep -c "<name>" || echo "0")
    echo "Turbine placemarks found: $TURBINE_PLACEMARKS_FOUND"
    
    # Extract placemark coordinates for turbine placemarks
    PLACEMARK_DATA=$(python3 << 'PYEOF'
import re
import json

try:
    with open("/home/ga/.googleearth/myplaces.kml", 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
    
    placemarks = []
    pm_pattern = r'<Placemark[^>]*>(.*?)</Placemark>'
    name_pattern = r'<name>(.*?)</name>'
    coord_pattern = r'<coordinates>([-\d.,\s]+)</coordinates>'
    
    for match in re.finditer(pm_pattern, content, re.DOTALL):
        pm_content = match.group(1)
        name_match = re.search(name_pattern, pm_content, re.IGNORECASE)
        coord_match = re.search(coord_pattern, pm_content)
        
        if name_match:
            name = name_match.group(1).strip()
            if 'turbine' in name.lower():
                coords = None
                if coord_match:
                    parts = coord_match.group(1).strip().split(',')
                    if len(parts) >= 2:
                        try:
                            coords = {"lon": float(parts[0]), "lat": float(parts[1])}
                        except:
                            pass
                placemarks.append({"name": name, "coords": coords})
    
    print(json.dumps(placemarks))
except Exception as e:
    print("[]")
PYEOF
)
fi

# ============================================================
# Check if Google Earth is running
# ============================================================
GE_RUNNING="false"
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# ============================================================
# Get window information
# ============================================================
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_screenshot": {
        "exists": $OUTPUT_EXISTS,
        "path": "$OUTPUT_PATH",
        "size_bytes": $OUTPUT_SIZE,
        "mtime": $OUTPUT_MTIME,
        "created_during_task": $FILE_CREATED_DURING_TASK
    },
    "final_screenshot": {
        "exists": $FINAL_SCREENSHOT_EXISTS,
        "path": "/tmp/task_final.png",
        "size_bytes": $FINAL_SCREENSHOT_SIZE
    },
    "myplaces": {
        "modified": $MYPLACES_MODIFIED,
        "initial_placemark_count": $INITIAL_PLACEMARK_COUNT,
        "current_placemark_count": $CURRENT_PLACEMARK_COUNT,
        "new_placemarks": $((CURRENT_PLACEMARK_COUNT - INITIAL_PLACEMARK_COUNT)),
        "turbine_placemarks_found": $TURBINE_PLACEMARKS_FOUND,
        "placemark_data": $PLACEMARK_DATA
    },
    "google_earth": {
        "running": $GE_RUNNING,
        "window_title": "$WINDOW_TITLE"
    }
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
echo ""
cat /tmp/task_result.json