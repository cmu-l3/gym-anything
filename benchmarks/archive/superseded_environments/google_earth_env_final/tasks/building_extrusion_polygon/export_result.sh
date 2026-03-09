#!/bin/bash
set -e
echo "=== Exporting 3D Building Extrusion task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot before checking results
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || true

# Define expected output paths
KML_PATH="/home/ga/Documents/proposed_building.kml"
SCREENSHOT_PATH="/home/ga/Documents/building_visualization.png"

# ============================================================
# Check KML file
# ============================================================
KML_EXISTS="false"
KML_CREATED_DURING_TASK="false"
KML_SIZE=0
KML_MTIME=0

if [ -f "$KML_PATH" ]; then
    KML_EXISTS="true"
    KML_SIZE=$(stat -c %s "$KML_PATH" 2>/dev/null || echo "0")
    KML_MTIME=$(stat -c %Y "$KML_PATH" 2>/dev/null || echo "0")
    
    if [ "$KML_MTIME" -gt "$TASK_START" ]; then
        KML_CREATED_DURING_TASK="true"
        echo "KML file was created during task"
    else
        echo "WARNING: KML file exists but was not created during task"
    fi
    
    echo "KML file: $KML_SIZE bytes"
    
    # Copy KML to temp for verification
    cp "$KML_PATH" /tmp/exported_building.kml 2>/dev/null || true
else
    echo "KML file not found at $KML_PATH"
fi

# ============================================================
# Check screenshot file
# ============================================================
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"
SCREENSHOT_SIZE=0
SCREENSHOT_MTIME=0

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    SCREENSHOT_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
        echo "Screenshot was created during task"
    else
        echo "WARNING: Screenshot exists but was not created during task"
    fi
    
    echo "Screenshot: $SCREENSHOT_SIZE bytes"
    
    # Copy screenshot to temp for verification
    cp "$SCREENSHOT_PATH" /tmp/exported_screenshot.png 2>/dev/null || true
else
    echo "Screenshot not found at $SCREENSHOT_PATH"
fi

# ============================================================
# Check Google Earth state
# ============================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

GE_WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")

# ============================================================
# Parse KML content if exists
# ============================================================
KML_HAS_POLYGON="false"
KML_HAS_EXTRUDE="false"
KML_HAS_ALTITUDE_MODE="false"
KML_ALTITUDE_VALUE=""
KML_POLYGON_NAME=""
KML_COORDINATES=""

if [ -f "$KML_PATH" ]; then
    # Check for polygon element
    if grep -qi "<Polygon>" "$KML_PATH" 2>/dev/null; then
        KML_HAS_POLYGON="true"
    fi
    
    # Check for extrude element
    if grep -qi "<extrude>1</extrude>" "$KML_PATH" 2>/dev/null; then
        KML_HAS_EXTRUDE="true"
    fi
    
    # Check for altitude mode
    if grep -qi "relativeToGround" "$KML_PATH" 2>/dev/null; then
        KML_HAS_ALTITUDE_MODE="true"
    fi
    
    # Extract polygon name (from Placemark > name)
    KML_POLYGON_NAME=$(grep -oP '(?<=<name>)[^<]+(?=</name>)' "$KML_PATH" 2>/dev/null | head -1 || echo "")
    
    # Extract coordinates (for location verification)
    KML_COORDINATES=$(grep -oP '(?<=<coordinates>)[^<]+(?=</coordinates>)' "$KML_PATH" 2>/dev/null | head -1 || echo "")
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "kml": {
        "exists": $KML_EXISTS,
        "created_during_task": $KML_CREATED_DURING_TASK,
        "size_bytes": $KML_SIZE,
        "mtime": $KML_MTIME,
        "has_polygon": $KML_HAS_POLYGON,
        "has_extrude": $KML_HAS_EXTRUDE,
        "has_altitude_mode_relative": $KML_HAS_ALTITUDE_MODE,
        "polygon_name": "$KML_POLYGON_NAME",
        "coordinates_sample": "$KML_COORDINATES"
    },
    "screenshot": {
        "exists": $SCREENSHOT_EXISTS,
        "created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
        "size_bytes": $SCREENSHOT_SIZE,
        "mtime": $SCREENSHOT_MTIME
    },
    "google_earth": {
        "running": $GE_RUNNING,
        "window_title": "$GE_WINDOW_TITLE"
    },
    "files": {
        "kml_path": "$KML_PATH",
        "screenshot_path": "$SCREENSHOT_PATH",
        "final_screenshot": "/tmp/task_final_screenshot.png"
    }
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="