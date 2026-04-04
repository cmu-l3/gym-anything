#!/bin/bash
echo "=== Exporting Center Pivot Irrigation Assessment result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# Check for KML/KMZ output files
KML_PATH="/home/ga/Documents/irrigation_pivot.kml"
KMZ_PATH="/home/ga/Documents/irrigation_pivot.kmz"

OUTPUT_EXISTS="false"
OUTPUT_PATH=""
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$KML_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_PATH="$KML_PATH"
    OUTPUT_SIZE=$(stat -c %s "$KML_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$KML_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Found KML file: $KML_PATH (${OUTPUT_SIZE} bytes)"
elif [ -f "$KMZ_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_PATH="$KMZ_PATH"
    OUTPUT_SIZE=$(stat -c %s "$KMZ_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$KMZ_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Found KMZ file: $KMZ_PATH (${OUTPUT_SIZE} bytes)"
else
    echo "No KML/KMZ output file found"
fi

# Check if Google Earth is still running
GE_RUNNING="false"
if pgrep -f google-earth-pro > /dev/null; then
    GE_RUNNING="true"
fi

# Get window information
WINDOW_TITLE=""
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

# Copy KML content for parsing (if exists)
KML_CONTENT=""
if [ -f "$KML_PATH" ]; then
    KML_CONTENT=$(cat "$KML_PATH" 2>/dev/null | head -c 10000 || echo "")
elif [ -f "$KMZ_PATH" ]; then
    # Extract KML from KMZ (it's a zip file)
    KML_CONTENT=$(unzip -p "$KMZ_PATH" "*.kml" 2>/dev/null | head -c 10000 || echo "")
fi

# Copy KML file to /tmp for easier access by verifier
if [ -f "$KML_PATH" ]; then
    cp "$KML_PATH" /tmp/output_irrigation.kml 2>/dev/null || true
    chmod 666 /tmp/output_irrigation.kml 2>/dev/null || true
elif [ -f "$KMZ_PATH" ]; then
    cp "$KMZ_PATH" /tmp/output_irrigation.kmz 2>/dev/null || true
    chmod 666 /tmp/output_irrigation.kmz 2>/dev/null || true
    # Also extract KML for easier parsing
    unzip -p "$KMZ_PATH" "*.kml" > /tmp/output_irrigation.kml 2>/dev/null || true
    chmod 666 /tmp/output_irrigation.kml 2>/dev/null || true
fi

# Create JSON result file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Escape KML content for JSON
KML_ESCAPED=$(echo "$KML_CONTENT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""')

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "google_earth_running": $GE_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "kml_content": $KML_ESCAPED,
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
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="