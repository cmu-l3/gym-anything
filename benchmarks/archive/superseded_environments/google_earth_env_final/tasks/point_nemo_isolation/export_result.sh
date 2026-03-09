#!/bin/bash
set -e
echo "=== Exporting Point Nemo Isolation Task Result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task end time: $TASK_END"
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot BEFORE any other operations
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    FINAL_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SIZE} bytes"
else
    echo "WARNING: Could not capture final screenshot"
fi

# ================================================================
# CHECK OUTPUT KML FILE
# ================================================================
OUTPUT_PATH="/home/ga/Documents/point_nemo_isolation.kml"
OUTPUT_PATH_KMZ="/home/ga/Documents/point_nemo_isolation.kmz"

OUTPUT_EXISTS="false"
OUTPUT_MTIME="0"
OUTPUT_SIZE="0"
FILE_CREATED_DURING_TASK="false"
KML_CONTENT=""

# Check for KML file first, then KMZ
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read KML content for analysis
    KML_CONTENT=$(cat "$OUTPUT_PATH" 2>/dev/null | head -c 50000 || echo "")
    echo "Found KML file: $OUTPUT_PATH ($OUTPUT_SIZE bytes)"
elif [ -f "$OUTPUT_PATH_KMZ" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_PATH="$OUTPUT_PATH_KMZ"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH_KMZ" 2>/dev/null || echo "0")
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH_KMZ" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Extract KML from KMZ (it's a zip file)
    if command -v unzip &> /dev/null; then
        KML_CONTENT=$(unzip -p "$OUTPUT_PATH_KMZ" "*.kml" 2>/dev/null | head -c 50000 || echo "")
    fi
    echo "Found KMZ file: $OUTPUT_PATH_KMZ ($OUTPUT_SIZE bytes)"
else
    echo "Output file NOT found at expected path"
fi

# ================================================================
# CHECK GOOGLE EARTH STATE
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Get window title
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "google earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

# ================================================================
# CHECK GOOGLE EARTH PLACES/STATE FILES
# ================================================================
MYPLACES_CONTENT=""
if [ -f "/home/ga/.googleearth/myplaces.kml" ]; then
    MYPLACES_CONTENT=$(cat "/home/ga/.googleearth/myplaces.kml" 2>/dev/null | head -c 20000 || echo "")
fi

# ================================================================
# ANALYZE KML CONTENT
# ================================================================
NUM_PLACEMARKS="0"
NUM_PATHS="0"
HAS_NEMO_PLACEMARK="false"
HAS_DUCIE_PLACEMARK="false"
HAS_PATH="false"

if [ -n "$KML_CONTENT" ]; then
    # Count placemarks
    NUM_PLACEMARKS=$(echo "$KML_CONTENT" | grep -c "<Placemark>" 2>/dev/null || echo "0")
    
    # Count paths/linestrings
    NUM_PATHS=$(echo "$KML_CONTENT" | grep -c "<LineString>" 2>/dev/null || echo "0")
    
    # Check for Point Nemo placemark
    if echo "$KML_CONTENT" | grep -qi "nemo\|oceanic.*pole"; then
        HAS_NEMO_PLACEMARK="true"
    fi
    
    # Check for Ducie Island placemark
    if echo "$KML_CONTENT" | grep -qi "ducie"; then
        HAS_DUCIE_PLACEMARK="true"
    fi
    
    # Check for path
    if [ "$NUM_PATHS" -gt "0" ]; then
        HAS_PATH="true"
    fi
fi

echo ""
echo "=== KML Analysis ==="
echo "Placemarks found: $NUM_PLACEMARKS"
echo "Paths found: $NUM_PATHS"
echo "Point Nemo placemark: $HAS_NEMO_PLACEMARK"
echo "Ducie Island placemark: $HAS_DUCIE_PLACEMARK"
echo "Has measurement path: $HAS_PATH"

# ================================================================
# CREATE JSON RESULT
# ================================================================
# Use a temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Escape KML content for JSON (basic escaping)
KML_ESCAPED=$(echo "$KML_CONTENT" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

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
    "window_title": "$GE_WINDOW_TITLE",
    "num_placemarks": $NUM_PLACEMARKS,
    "num_paths": $NUM_PATHS,
    "has_nemo_placemark": $HAS_NEMO_PLACEMARK,
    "has_ducie_placemark": $HAS_DUCIE_PLACEMARK,
    "has_path": $HAS_PATH,
    "kml_content": $KML_ESCAPED,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json | python3 -c "import sys,json; d=json.load(sys.stdin); del d['kml_content']; print(json.dumps(d, indent=2))" 2>/dev/null || cat /tmp/task_result.json