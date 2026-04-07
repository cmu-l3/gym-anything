#!/bin/bash
echo "=== Exporting screen_overlay_compass task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_screenshots/final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_screenshots/final_state.png 2>/dev/null || true

# Check if KML output file exists and was created during task
OUTPUT_PATH="/home/ga/Documents/compass_overlay.kml"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"
KML_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read KML content for analysis
    KML_CONTENT=$(cat "$OUTPUT_PATH" 2>/dev/null | base64 -w 0 || echo "")
fi

# Check for ScreenOverlay vs GroundOverlay in KML
HAS_SCREEN_OVERLAY="false"
HAS_GROUND_OVERLAY="false"
HAS_COMPASS_NAME="false"
HAS_WIKIPEDIA_IMAGE="false"
SCREEN_X_VALUE=""
SCREEN_Y_VALUE=""

if [ -f "$OUTPUT_PATH" ]; then
    # Check for ScreenOverlay element
    if grep -q "<ScreenOverlay" "$OUTPUT_PATH" 2>/dev/null; then
        HAS_SCREEN_OVERLAY="true"
    fi
    
    # Check for GroundOverlay (wrong approach)
    if grep -q "<GroundOverlay" "$OUTPUT_PATH" 2>/dev/null; then
        HAS_GROUND_OVERLAY="true"
    fi
    
    # Check for compass-related name
    if grep -qi "compass\|legend" "$OUTPUT_PATH" 2>/dev/null; then
        HAS_COMPASS_NAME="true"
    fi
    
    # Check for Wikipedia/Wikimedia image URL
    if grep -qi "wikipedia\|wikimedia\|Brosen_windrose" "$OUTPUT_PATH" 2>/dev/null; then
        HAS_WIKIPEDIA_IMAGE="true"
    fi
    
    # Extract screenXY values
    SCREEN_XY_LINE=$(grep -o '<screenXY[^>]*>' "$OUTPUT_PATH" 2>/dev/null | head -1 || echo "")
    if [ -n "$SCREEN_XY_LINE" ]; then
        SCREEN_X_VALUE=$(echo "$SCREEN_XY_LINE" | grep -o 'x="[0-9.]*"' | grep -o '[0-9.]*' | head -1 || echo "")
        SCREEN_Y_VALUE=$(echo "$SCREEN_XY_LINE" | grep -o 'y="[0-9.]*"' | grep -o '[0-9.]*' | head -1 || echo "")
    fi
fi

# Check if Google Earth is still running
GE_RUNNING="false"
if pgrep -f google-earth-pro > /dev/null; then
    GE_RUNNING="true"
fi

# Get window information
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")

# Count screenshots in trajectory folder (if available)
TRAJECTORY_SCREENSHOT_COUNT=0
if [ -d "/tmp/task_screenshots" ]; then
    TRAJECTORY_SCREENSHOT_COUNT=$(ls -1 /tmp/task_screenshots/*.png 2>/dev/null | wc -l || echo "0")
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_file": {
        "path": "$OUTPUT_PATH",
        "exists": $OUTPUT_EXISTS,
        "size_bytes": $OUTPUT_SIZE,
        "mtime": $OUTPUT_MTIME,
        "created_during_task": $FILE_CREATED_DURING_TASK
    },
    "kml_analysis": {
        "has_screen_overlay": $HAS_SCREEN_OVERLAY,
        "has_ground_overlay": $HAS_GROUND_OVERLAY,
        "has_compass_name": $HAS_COMPASS_NAME,
        "has_wikipedia_image": $HAS_WIKIPEDIA_IMAGE,
        "screen_x_value": "$SCREEN_X_VALUE",
        "screen_y_value": "$SCREEN_Y_VALUE"
    },
    "application_state": {
        "google_earth_running": $GE_RUNNING,
        "active_window_title": "$WINDOW_TITLE",
        "ge_windows": "$GE_WINDOWS"
    },
    "evidence": {
        "final_screenshot": "/tmp/task_screenshots/final_state.png",
        "trajectory_screenshot_count": $TRAJECTORY_SCREENSHOT_COUNT
    },
    "kml_content_base64": "$KML_CONTENT"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results ==="
echo "KML file exists: $OUTPUT_EXISTS"
echo "Created during task: $FILE_CREATED_DURING_TASK"
echo "Has ScreenOverlay: $HAS_SCREEN_OVERLAY"
echo "Has GroundOverlay (wrong): $HAS_GROUND_OVERLAY"
echo "Has compass name: $HAS_COMPASS_NAME"
echo "Has Wikipedia image: $HAS_WIKIPEDIA_IMAGE"
echo "Screen X value: $SCREEN_X_VALUE"
echo "Screen Y value: $SCREEN_Y_VALUE"
echo ""

cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="