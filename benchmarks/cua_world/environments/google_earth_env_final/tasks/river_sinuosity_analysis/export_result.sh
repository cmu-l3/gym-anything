#!/bin/bash
set -e
echo "=== Exporting River Sinuosity Analysis task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot BEFORE any other operations
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
    SCREENSHOT_SIZE="0"
fi

# Check if KML output file exists
KML_PATH="/home/ga/Documents/mississippi_sinuosity.kml"
if [ -f "$KML_PATH" ]; then
    KML_EXISTS="true"
    KML_SIZE=$(stat -c %s "$KML_PATH" 2>/dev/null || echo "0")
    KML_MTIME=$(stat -c %Y "$KML_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$KML_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Extract KML content for verification
    KML_CONTENT=$(cat "$KML_PATH" 2>/dev/null | head -c 50000 || echo "")
    
    # Count placemarks in KML
    PLACEMARK_COUNT=$(grep -c "<Placemark>" "$KML_PATH" 2>/dev/null || echo "0")
    
    # Check for expected placemark names
    HAS_START=$(grep -q "Sinuosity_Start\|sinuosity_start\|Start" "$KML_PATH" 2>/dev/null && echo "true" || echo "false")
    HAS_END=$(grep -q "Sinuosity_End\|sinuosity_end\|End" "$KML_PATH" 2>/dev/null && echo "true" || echo "false")
    HAS_ANALYSIS=$(grep -q "Sinuosity_Analysis\|sinuosity_analysis\|Analysis" "$KML_PATH" 2>/dev/null && echo "true" || echo "false")
    
    # Check for folder
    HAS_FOLDER=$(grep -q "Mississippi_Sinuosity\|mississippi_sinuosity\|Sinuosity" "$KML_PATH" 2>/dev/null && echo "true" || echo "false")
    
    # Copy KML to temp for verification
    cp "$KML_PATH" /tmp/exported_kml.kml 2>/dev/null || true
    chmod 644 /tmp/exported_kml.kml 2>/dev/null || true
else
    KML_EXISTS="false"
    KML_SIZE="0"
    KML_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
    PLACEMARK_COUNT="0"
    HAS_START="false"
    HAS_END="false"
    HAS_ANALYSIS="false"
    HAS_FOLDER="false"
fi

# Check Google Earth state
if pgrep -f "google-earth" > /dev/null; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f "google-earth" | head -1)
else
    GE_RUNNING="false"
    GE_PID="0"
fi

# Get window information
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")

# Check for any KML files in common locations
OTHER_KML_FILES=$(find /home/ga -name "*.kml" -type f 2>/dev/null | head -10 || echo "")

# Check Google Earth's myplaces.kml for recent additions
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
if [ -f "$MYPLACES_PATH" ]; then
    MYPLACES_EXISTS="true"
    MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_PATH" 2>/dev/null || echo "0")
    MYPLACES_HAS_SINUOSITY=$(grep -qi "sinuosity\|mississippi" "$MYPLACES_PATH" 2>/dev/null && echo "true" || echo "false")
    # Copy for verification
    cp "$MYPLACES_PATH" /tmp/myplaces_backup.kml 2>/dev/null || true
    chmod 644 /tmp/myplaces_backup.kml 2>/dev/null || true
else
    MYPLACES_EXISTS="false"
    MYPLACES_MTIME="0"
    MYPLACES_HAS_SINUOSITY="false"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "kml_output": {
        "exists": $KML_EXISTS,
        "path": "$KML_PATH",
        "size_bytes": $KML_SIZE,
        "mtime": $KML_MTIME,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "placemark_count": $PLACEMARK_COUNT,
        "has_start_placemark": $HAS_START,
        "has_end_placemark": $HAS_END,
        "has_analysis_placemark": $HAS_ANALYSIS,
        "has_folder": $HAS_FOLDER
    },
    "myplaces": {
        "exists": $MYPLACES_EXISTS,
        "mtime": $MYPLACES_MTIME,
        "has_sinuosity_content": $MYPLACES_HAS_SINUOSITY
    },
    "google_earth": {
        "running": $GE_RUNNING,
        "pid": "$GE_PID",
        "window_title": "$WINDOW_TITLE"
    },
    "screenshot": {
        "exists": $SCREENSHOT_EXISTS,
        "path": "/tmp/task_final.png",
        "size_bytes": $SCREENSHOT_SIZE
    }
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Summary ==="
echo "KML exists: $KML_EXISTS"
echo "KML size: $KML_SIZE bytes"
echo "Created during task: $FILE_CREATED_DURING_TASK"
echo "Placemark count: $PLACEMARK_COUNT"
echo "Has start/end/analysis: $HAS_START / $HAS_END / $HAS_ANALYSIS"
echo "Google Earth running: $GE_RUNNING"
echo ""
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="