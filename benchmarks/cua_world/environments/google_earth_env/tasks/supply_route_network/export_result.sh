#!/bin/bash
echo "=== Exporting Supply Route Network task results ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Capture final screenshot BEFORE any other operations
echo "Capturing final state screenshot..."
sleep 1
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

# Check output KML file
OUTPUT_PATH="/home/ga/Documents/chicago_distribution_network.kml"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task (anti-gaming)
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "KML file was created during task execution"
    else
        echo "WARNING: KML file exists but was NOT created during task"
    fi
    
    echo "Output file: $OUTPUT_PATH"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $(date -d @$OUTPUT_MTIME)"
else
    echo "Output file NOT found: $OUTPUT_PATH"
fi

# Check for any KML files in Documents (agent might have used different name)
echo ""
echo "--- All KML files in Documents ---"
ls -la /home/ga/Documents/*.kml 2>/dev/null || echo "No KML files found"

# Count KML files
FINAL_KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
INITIAL_KML_COUNT=$(cat /tmp/initial_kml_count.txt 2>/dev/null || echo "0")
NEW_KML_FILES=$((FINAL_KML_COUNT - INITIAL_KML_COUNT))
echo "New KML files created: $NEW_KML_FILES"

# Check if Google Earth is still running
GE_RUNNING="false"
GE_PID=""
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f google-earth-pro | head -1)
fi
echo "Google Earth running: $GE_RUNNING (PID: $GE_PID)"

# Get Google Earth window info
GE_WINDOW_TITLE=""
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi
echo "Google Earth window: $GE_WINDOW_TITLE"

# Parse KML content if file exists (basic extraction)
KML_HAS_FOLDER="false"
KML_FOLDER_NAME=""
KML_PATH_COUNT="0"
KML_HAS_LINESTRING="false"
KML_HAS_RED_STYLE="false"
KML_HAS_BLUE_STYLE="false"

if [ -f "$OUTPUT_PATH" ]; then
    echo ""
    echo "--- Analyzing KML structure ---"
    
    # Check for Folder element
    if grep -qi "<Folder>" "$OUTPUT_PATH" 2>/dev/null; then
        KML_HAS_FOLDER="true"
        # Try to extract folder name
        KML_FOLDER_NAME=$(grep -oP '(?<=<name>)[^<]+(?=</name>)' "$OUTPUT_PATH" 2>/dev/null | head -1 || echo "")
        echo "Folder found: $KML_FOLDER_NAME"
    fi
    
    # Count Placemark elements (paths are stored as Placemarks)
    KML_PATH_COUNT=$(grep -c "<Placemark>" "$OUTPUT_PATH" 2>/dev/null || echo "0")
    echo "Placemarks found: $KML_PATH_COUNT"
    
    # Check for LineString (path geometry)
    if grep -qi "<LineString>" "$OUTPUT_PATH" 2>/dev/null; then
        KML_HAS_LINESTRING="true"
        LINESTRING_COUNT=$(grep -c "<LineString>" "$OUTPUT_PATH" 2>/dev/null || echo "0")
        echo "LineString elements: $LINESTRING_COUNT"
    fi
    
    # Check for color styles (KML uses aabbggrr format)
    # Red = ff0000ff or similar with high red component
    if grep -qi "ff0000\|0000ff" "$OUTPUT_PATH" 2>/dev/null; then
        # KML stores colors as aabbggrr (alpha, blue, green, red)
        # Red in KML = ff0000ff (full alpha, no blue, no green, full red)
        if grep -qiE "ff[0-9a-f]{2}0000" "$OUTPUT_PATH" 2>/dev/null; then
            KML_HAS_RED_STYLE="true"
            echo "Red style detected"
        fi
    fi
    
    # Blue in KML = ffff0000 (full alpha, full blue, no green, no red)
    if grep -qiE "ff[f][f]0000|ffff00" "$OUTPUT_PATH" 2>/dev/null; then
        KML_HAS_BLUE_STYLE="true"
        echo "Blue style detected"
    fi
    
    # Show first 100 lines of KML for debugging
    echo ""
    echo "--- KML content preview (first 100 lines) ---"
    head -100 "$OUTPUT_PATH" 2>/dev/null || echo "Could not read KML file"
fi

# Copy KML file to /tmp for easy retrieval by verifier
if [ -f "$OUTPUT_PATH" ]; then
    cp "$OUTPUT_PATH" /tmp/task_output.kml 2>/dev/null || true
    chmod 644 /tmp/task_output.kml 2>/dev/null || true
fi

# Create JSON result file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_path": "$OUTPUT_PATH",
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "new_kml_files_created": $NEW_KML_FILES,
    "google_earth_running": $GE_RUNNING,
    "google_earth_pid": "$GE_PID",
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final_state.png",
    "kml_analysis": {
        "has_folder": $KML_HAS_FOLDER,
        "folder_name": "$KML_FOLDER_NAME",
        "placemark_count": $KML_PATH_COUNT,
        "has_linestring": $KML_HAS_LINESTRING,
        "has_red_style": $KML_HAS_RED_STYLE,
        "has_blue_style": $KML_HAS_BLUE_STYLE
    }
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