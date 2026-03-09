#!/bin/bash
echo "=== Exporting SAR Grid Creation task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task end time: $TASK_END"
echo "Task start time: $TASK_START"

# Capture final screenshot FIRST (before any state changes)
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
fi

# Check expected output file
OUTPUT_PATH="/home/ga/Documents/SAR_MarcusChen_Grid.kml"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created/modified during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "KML file was created/modified during task"
    else
        echo "WARNING: KML file exists but was not modified during task (potential gaming)"
    fi
    
    echo "Output file found: $OUTPUT_PATH"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $OUTPUT_MTIME"
else
    echo "Output file NOT found: $OUTPUT_PATH"
fi

# Check for any KML files in Documents
KML_FILES=$(ls -la /home/ga/Documents/*.kml 2>/dev/null || echo "none")
echo "KML files in Documents:"
echo "$KML_FILES"

# Check if Google Earth is still running
GE_RUNNING="false"
GE_PID=""
if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f "google-earth" | head -1)
fi
echo "Google Earth running: $GE_RUNNING (PID: $GE_PID)"

# Get Google Earth window info
GE_WINDOW_TITLE=""
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi
echo "Google Earth window: $GE_WINDOW_TITLE"

# If KML exists, extract some content info for verification
KML_CONTENT_INFO="{}"
if [ "$OUTPUT_EXISTS" = "true" ]; then
    # Check for key elements in KML (basic parsing)
    HAS_FOLDER=$(grep -c "<Folder>" "$OUTPUT_PATH" 2>/dev/null || echo "0")
    HAS_POLYGON=$(grep -c "<Polygon>" "$OUTPUT_PATH" 2>/dev/null || echo "0")
    HAS_LINESTRING=$(grep -c "<LineString>" "$OUTPUT_PATH" 2>/dev/null || echo "0")
    HAS_POINT=$(grep -c "<Point>" "$OUTPUT_PATH" 2>/dev/null || echo "0")
    HAS_PLACEMARK=$(grep -c "<Placemark>" "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check for expected names
    HAS_SAR_FOLDER=$(grep -c "SAR_MarcusChen" "$OUTPUT_PATH" 2>/dev/null || echo "0")
    HAS_BOUNDARY=$(grep -c "Search_Boundary" "$OUTPUT_PATH" 2>/dev/null || echo "0")
    HAS_DIVIDER=$(grep -c "Divider" "$OUTPUT_PATH" 2>/dev/null || echo "0")
    HAS_SECTOR=$(grep -c "Sector_" "$OUTPUT_PATH" 2>/dev/null || echo "0")
    HAS_LKP=$(grep -c "LKP_" "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    echo ""
    echo "KML Content Summary:"
    echo "  Folders: $HAS_FOLDER"
    echo "  Polygons: $HAS_POLYGON"
    echo "  LineStrings: $HAS_LINESTRING"
    echo "  Points: $HAS_POINT"
    echo "  Placemarks: $HAS_PLACEMARK"
    echo "  SAR folder name: $HAS_SAR_FOLDER"
    echo "  Boundary name: $HAS_BOUNDARY"
    echo "  Divider names: $HAS_DIVIDER"
    echo "  Sector names: $HAS_SECTOR"
    echo "  LKP name: $HAS_LKP"
    
    KML_CONTENT_INFO=$(cat << KMLEOF
{
        "folders": $HAS_FOLDER,
        "polygons": $HAS_POLYGON,
        "linestrings": $HAS_LINESTRING,
        "points": $HAS_POINT,
        "placemarks": $HAS_PLACEMARK,
        "has_sar_folder_name": $([ "$HAS_SAR_FOLDER" -gt 0 ] && echo "true" || echo "false"),
        "has_boundary_name": $([ "$HAS_BOUNDARY" -gt 0 ] && echo "true" || echo "false"),
        "has_divider_names": $([ "$HAS_DIVIDER" -gt 0 ] && echo "true" || echo "false"),
        "has_sector_names": $([ "$HAS_SECTOR" -gt 0 ] && echo "true" || echo "false"),
        "has_lkp_name": $([ "$HAS_LKP" -gt 0 ] && echo "true" || echo "false")
    }
KMLEOF
)
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
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
    "google_earth_pid": "$GE_PID",
    "google_earth_window": "$GE_WINDOW_TITLE",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final_state.png",
    "kml_content_info": $KML_CONTENT_INFO
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Result JSON ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="