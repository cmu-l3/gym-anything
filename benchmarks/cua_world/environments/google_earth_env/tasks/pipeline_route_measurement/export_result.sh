#!/bin/bash
set -euo pipefail

echo "=== Exporting pipeline_route_measurement task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_final_screenshot.png ]; then
    SIZE=$(stat -c %s /tmp/task_final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Check primary output file
OUTPUT_PATH="/home/ga/Documents/TAPS_Fairbanks_Valdez.kml"
ALT_KMZ="/home/ga/Documents/TAPS_Fairbanks_Valdez.kmz"
MYPLACES="/home/ga/.googleearth/myplaces.kml"

OUTPUT_EXISTS="false"
OUTPUT_FILE=""
OUTPUT_SIZE=0
OUTPUT_MTIME=0
FILE_CREATED_DURING_TASK="false"

# Check primary KML output
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_FILE="$OUTPUT_PATH"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Found KML output: $OUTPUT_PATH (${OUTPUT_SIZE} bytes)"
# Check alternative KMZ output
elif [ -f "$ALT_KMZ" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_FILE="$ALT_KMZ"
    OUTPUT_SIZE=$(stat -c%s "$ALT_KMZ" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$ALT_KMZ" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Found KMZ output: $ALT_KMZ (${OUTPUT_SIZE} bytes)"
fi

# Check myplaces.kml for saved path
MYPLACES_UPDATED="false"
MYPLACES_SIZE=0
MYPLACES_CONTAINS_PATH="false"
INITIAL_MYPLACES_SIZE=$(python3 -c "import json; print(json.load(open('/tmp/initial_file_state.json')).get('myplaces_size', 0))" 2>/dev/null || echo "0")
INITIAL_MYPLACES_MTIME=$(python3 -c "import json; print(json.load(open('/tmp/initial_file_state.json')).get('myplaces_mtime', 0))" 2>/dev/null || echo "0")

if [ -f "$MYPLACES" ]; then
    MYPLACES_SIZE=$(stat -c%s "$MYPLACES" 2>/dev/null || echo "0")
    MYPLACES_MTIME=$(stat -c%Y "$MYPLACES" 2>/dev/null || echo "0")
    
    if [ "$MYPLACES_MTIME" -gt "$INITIAL_MYPLACES_MTIME" ] || [ "$MYPLACES_SIZE" -ne "$INITIAL_MYPLACES_SIZE" ]; then
        MYPLACES_UPDATED="true"
    fi
    
    # Check if myplaces contains a path/linestring related to TAPS or Alaska
    if grep -qi "LineString\|Path\|TAPS\|Alaska\|Fairbanks\|Valdez" "$MYPLACES" 2>/dev/null; then
        MYPLACES_CONTAINS_PATH="true"
        echo "myplaces.kml contains relevant path data"
    fi
fi

# Check if Google Earth is still running
GE_RUNNING="false"
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Get window title
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")

# Check for any KML/KMZ files created in Documents during the task
RECENT_KML_FILES=""
if [ -d "/home/ga/Documents" ]; then
    RECENT_KML_FILES=$(find /home/ga/Documents -maxdepth 1 \( -name "*.kml" -o -name "*.kmz" \) -newermt "@$TASK_START" 2>/dev/null | tr '\n' '|' || echo "")
fi

# Extract path data from output file if it exists
PATH_DATA=""
PATH_COORDINATES=""
PATH_LENGTH_ESTIMATE=""

if [ "$OUTPUT_EXISTS" = "true" ] && [ -f "$OUTPUT_FILE" ]; then
    echo "Extracting path data from output file..."
    
    # For KML files, extract coordinates
    if [[ "$OUTPUT_FILE" == *.kml ]]; then
        PATH_COORDINATES=$(grep -oP '<coordinates>[^<]+</coordinates>' "$OUTPUT_FILE" 2>/dev/null | head -1 || echo "")
        
        # Count coordinate pairs
        if [ -n "$PATH_COORDINATES" ]; then
            COORD_COUNT=$(echo "$PATH_COORDINATES" | grep -oP '[-0-9.]+,[-0-9.]+' | wc -l || echo "0")
            echo "Found $COORD_COUNT coordinate pairs in path"
        fi
    fi
    
    # For KMZ files, extract and parse
    if [[ "$OUTPUT_FILE" == *.kmz ]]; then
        TEMP_DIR=$(mktemp -d)
        unzip -q "$OUTPUT_FILE" -d "$TEMP_DIR" 2>/dev/null || true
        if [ -f "$TEMP_DIR/doc.kml" ]; then
            PATH_COORDINATES=$(grep -oP '<coordinates>[^<]+</coordinates>' "$TEMP_DIR/doc.kml" 2>/dev/null | head -1 || echo "")
        fi
        rm -rf "$TEMP_DIR"
    fi
fi

# Also check myplaces if no explicit output
if [ "$OUTPUT_EXISTS" = "false" ] && [ "$MYPLACES_CONTAINS_PATH" = "true" ]; then
    echo "Checking myplaces.kml for path data..."
    # Extract recent LineString from myplaces
    PATH_COORDINATES=$(grep -oP '<coordinates>[^<]+</coordinates>' "$MYPLACES" 2>/dev/null | tail -1 || echo "")
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_exists": $OUTPUT_EXISTS,
    "output_file": "$OUTPUT_FILE",
    "output_size_bytes": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "myplaces_updated": $MYPLACES_UPDATED,
    "myplaces_contains_path": $MYPLACES_CONTAINS_PATH,
    "myplaces_size": $MYPLACES_SIZE,
    "google_earth_running": $GE_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "recent_kml_files": "$RECENT_KML_FILES",
    "path_coordinates_found": $([ -n "$PATH_COORDINATES" ] && echo "true" || echo "false"),
    "final_screenshot": "/tmp/task_final_screenshot.png"
}
EOF

# Copy path coordinates to separate file for parsing
if [ -n "$PATH_COORDINATES" ]; then
    echo "$PATH_COORDINATES" > /tmp/path_coordinates.txt
    echo "Path coordinates saved to /tmp/path_coordinates.txt"
fi

# Move result to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Copy the output file to /tmp for easy access
if [ "$OUTPUT_EXISTS" = "true" ] && [ -f "$OUTPUT_FILE" ]; then
    cp "$OUTPUT_FILE" /tmp/pipeline_output.kml 2>/dev/null || true
    chmod 666 /tmp/pipeline_output.kml 2>/dev/null || true
fi

# Also copy myplaces if relevant
if [ "$MYPLACES_CONTAINS_PATH" = "true" ] && [ -f "$MYPLACES" ]; then
    cp "$MYPLACES" /tmp/myplaces_copy.kml 2>/dev/null || true
    chmod 666 /tmp/myplaces_copy.kml 2>/dev/null || true
fi

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json