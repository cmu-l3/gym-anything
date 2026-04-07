#!/bin/bash
set -e
echo "=== Exporting equator_ecuador_segment task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE any other operations
echo "Capturing final state..."
scrot /tmp/task_final_state.png 2>/dev/null || true

# Check if output KML file exists and its properties
OUTPUT_PATH="/home/ga/Documents/ecuador_equator.kml"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task (anti-gaming)
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "KML file was created during task execution"
    else
        echo "WARNING: KML file predates task start time"
    fi
fi

# Check if Google Earth is still running
GE_RUNNING=$(pgrep -f google-earth-pro > /dev/null && echo "true" || echo "false")

# Get window information
WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
GE_WINDOWS=$(wmctrl -l 2>/dev/null | grep -iE "(google earth|earth pro)" || echo "none")

# Count KML files in Documents
FINAL_KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
INITIAL_KML_COUNT=$(cat /tmp/initial_kml_count.txt 2>/dev/null || echo "0")

# Extract basic KML info if file exists
KML_HAS_FOLDER="false"
KML_HAS_PATH="false"
KML_HAS_PLACEMARK="false"
KML_PATH_COORDS=""
KML_PLACEMARK_COORDS=""

if [ -f "$OUTPUT_PATH" ] && [ "$OUTPUT_SIZE" -gt "0" ]; then
    # Check for folder
    if grep -qi "<Folder>" "$OUTPUT_PATH" 2>/dev/null; then
        KML_HAS_FOLDER="true"
    fi
    
    # Check for path/linestring
    if grep -qi "<LineString>" "$OUTPUT_PATH" 2>/dev/null; then
        KML_HAS_PATH="true"
    fi
    
    # Check for placemark with Point
    if grep -qi "<Point>" "$OUTPUT_PATH" 2>/dev/null; then
        KML_HAS_PLACEMARK="true"
    fi
fi

# Copy KML file to tmp for verifier access
if [ -f "$OUTPUT_PATH" ]; then
    cp "$OUTPUT_PATH" /tmp/ecuador_equator.kml 2>/dev/null || true
    chmod 644 /tmp/ecuador_equator.kml 2>/dev/null || true
fi

# Also check myplaces.kml for any created content
if [ -f "/home/ga/.googleearth/myplaces.kml" ]; then
    cp /home/ga/.googleearth/myplaces.kml /tmp/myplaces_final.kml 2>/dev/null || true
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "google_earth_running": $GE_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "initial_kml_count": $INITIAL_KML_COUNT,
    "final_kml_count": $FINAL_KML_COUNT,
    "kml_has_folder": $KML_HAS_FOLDER,
    "kml_has_path": $KML_HAS_PATH,
    "kml_has_placemark": $KML_HAS_PLACEMARK,
    "screenshot_path": "/tmp/task_final_state.png",
    "kml_copy_path": "/tmp/ecuador_equator.kml"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results ==="
echo "Output file exists: $OUTPUT_EXISTS"
echo "File created during task: $FILE_CREATED_DURING_TASK"
echo "Output size: $OUTPUT_SIZE bytes"
echo "KML has folder: $KML_HAS_FOLDER"
echo "KML has path: $KML_HAS_PATH"
echo "KML has placemark: $KML_HAS_PLACEMARK"
echo "Google Earth running: $GE_RUNNING"
echo ""
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="