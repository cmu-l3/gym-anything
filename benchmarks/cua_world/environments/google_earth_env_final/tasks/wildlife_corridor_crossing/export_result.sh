#!/bin/bash
set -euo pipefail

echo "=== Exporting Wildlife Corridor Crossing task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task start time: $TASK_START"
echo "Task end time: $TASK_END"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || true
echo "Final screenshot captured"

# ================================================================
# Check KML output file
# ================================================================
KML_PATH="/home/ga/Documents/mara_crossing.kml"
KML_EXISTS="false"
KML_SIZE="0"
KML_MTIME="0"
KML_CREATED_DURING_TASK="false"
KML_CONTENT=""
KML_COORDINATES=""
KML_NAME=""
KML_DESCRIPTION=""

if [ -f "$KML_PATH" ]; then
    KML_EXISTS="true"
    KML_SIZE=$(stat -c %s "$KML_PATH" 2>/dev/null || echo "0")
    KML_MTIME=$(stat -c %Y "$KML_PATH" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$KML_MTIME" -gt "$TASK_START" ]; then
        KML_CREATED_DURING_TASK="true"
    fi
    
    # Read KML content (first 5000 chars for JSON safety)
    KML_CONTENT=$(head -c 5000 "$KML_PATH" 2>/dev/null | tr '\n' ' ' | tr '"' "'" || echo "")
    
    # Try to extract coordinates using grep/sed
    KML_COORDINATES=$(grep -oP '(?<=<coordinates>)[^<]+' "$KML_PATH" 2>/dev/null | head -1 || echo "")
    
    # Try to extract placemark name
    KML_NAME=$(grep -oP '(?<=<name>)[^<]+' "$KML_PATH" 2>/dev/null | head -1 || echo "")
    
    # Try to extract description
    KML_DESCRIPTION=$(grep -oP '(?<=<description>)[^<]+' "$KML_PATH" 2>/dev/null | head -1 || echo "")
    
    echo "KML file found: $KML_PATH"
    echo "  Size: $KML_SIZE bytes"
    echo "  Modified: $KML_MTIME"
    echo "  Created during task: $KML_CREATED_DURING_TASK"
    echo "  Coordinates: $KML_COORDINATES"
    echo "  Name: $KML_NAME"
    echo "  Description: $KML_DESCRIPTION"
else
    echo "KML file NOT found at $KML_PATH"
fi

# ================================================================
# Check screenshot output file
# ================================================================
PNG_PATH="/home/ga/Documents/mara_crossing_view.png"
PNG_EXISTS="false"
PNG_SIZE="0"
PNG_MTIME="0"
PNG_CREATED_DURING_TASK="false"

if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c %Y "$PNG_PATH" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_CREATED_DURING_TASK="true"
    fi
    
    echo "Screenshot file found: $PNG_PATH"
    echo "  Size: $PNG_SIZE bytes"
    echo "  Modified: $PNG_MTIME"
    echo "  Created during task: $PNG_CREATED_DURING_TASK"
else
    echo "Screenshot file NOT found at $PNG_PATH"
fi

# ================================================================
# Check Google Earth state
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

echo "Google Earth running: $GE_RUNNING"
echo "Window title: $GE_WINDOW_TITLE"

# ================================================================
# Check for My Places entries
# ================================================================
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
MYPLACES_HAS_MARA="false"
MYPLACES_CONTENT=""

if [ -f "$MYPLACES_PATH" ]; then
    # Check if myplaces contains our placemark
    if grep -qi "mara" "$MYPLACES_PATH" 2>/dev/null; then
        MYPLACES_HAS_MARA="true"
    fi
    MYPLACES_CONTENT=$(grep -i "mara\|crossing" "$MYPLACES_PATH" 2>/dev/null | head -5 | tr '\n' ' ' | tr '"' "'" || echo "")
fi

echo "My Places has Mara reference: $MYPLACES_HAS_MARA"

# ================================================================
# Create JSON result file
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "kml": {
        "exists": $KML_EXISTS,
        "size_bytes": $KML_SIZE,
        "mtime": $KML_MTIME,
        "created_during_task": $KML_CREATED_DURING_TASK,
        "coordinates": "$KML_COORDINATES",
        "name": "$KML_NAME",
        "description": "$KML_DESCRIPTION"
    },
    "screenshot": {
        "exists": $PNG_EXISTS,
        "size_bytes": $PNG_SIZE,
        "mtime": $PNG_MTIME,
        "created_during_task": $PNG_CREATED_DURING_TASK
    },
    "google_earth": {
        "running": $GE_RUNNING,
        "window_title": "$GE_WINDOW_TITLE"
    },
    "myplaces": {
        "has_mara_reference": $MYPLACES_HAS_MARA,
        "content_snippet": "$MYPLACES_CONTENT"
    },
    "final_screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json