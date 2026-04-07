#!/bin/bash
echo "=== Exporting Lighthouse Visibility Range task result ==="

export DISPLAY=${DISPLAY:-:1}

# ================================================================
# Record task end time
# ================================================================
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# ================================================================
# Take final screenshot FIRST (for VLM verification)
# ================================================================
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
    SCREENSHOT_SIZE="0"
fi

# ================================================================
# Check expected KML output file
# ================================================================
OUTPUT_PATH="/home/ga/Documents/cape_hatteras_visibility.kml"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created/modified during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Copy KML content for verification (first 10KB to avoid huge files)
    KML_CONTENT=$(head -c 10240 "$OUTPUT_PATH" 2>/dev/null | base64 -w 0 || echo "")
    
    echo "Output file found:"
    echo "  Path: $OUTPUT_PATH"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $(date -d @$OUTPUT_MTIME 2>/dev/null || echo $OUTPUT_MTIME)"
    echo "  Created during task: $FILE_CREATED_DURING_TASK"
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
    KML_CONTENT=""
    echo "Output file NOT found at $OUTPUT_PATH"
fi

# ================================================================
# Check for any KML files in Documents directory
# ================================================================
KML_FILES_FOUND=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
echo "Total KML files in Documents: $KML_FILES_FOUND"

if [ "$KML_FILES_FOUND" -gt "0" ]; then
    echo "KML files present:"
    ls -la /home/ga/Documents/*.kml 2>/dev/null || true
fi

# ================================================================
# Check Google Earth state
# ================================================================
GE_RUNNING="false"
GE_PID=""
GE_WINDOW_TITLE=""

if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f "google-earth-pro" | head -1)
fi

# Get window title
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

echo "Google Earth status:"
echo "  Running: $GE_RUNNING"
echo "  PID: $GE_PID"
echo "  Window: $GE_WINDOW_TITLE"

# ================================================================
# Check Google Earth's internal state files
# ================================================================
MYPLACES_EXISTS="false"
MYPLACES_SIZE="0"
MYPLACES_CONTENT=""

if [ -f "/home/ga/.googleearth/myplaces.kml" ]; then
    MYPLACES_EXISTS="true"
    MYPLACES_SIZE=$(stat -c %s "/home/ga/.googleearth/myplaces.kml" 2>/dev/null || echo "0")
    MYPLACES_CONTENT=$(head -c 5120 "/home/ga/.googleearth/myplaces.kml" 2>/dev/null | base64 -w 0 || echo "")
fi

# ================================================================
# Create JSON result file
# ================================================================
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
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "content_base64": "$KML_CONTENT"
    },
    "kml_files_count": $KML_FILES_FOUND,
    "google_earth": {
        "running": $GE_RUNNING,
        "pid": "$GE_PID",
        "window_title": "$GE_WINDOW_TITLE"
    },
    "myplaces": {
        "exists": $MYPLACES_EXISTS,
        "size_bytes": $MYPLACES_SIZE,
        "content_base64": "$MYPLACES_CONTENT"
    },
    "screenshot": {
        "exists": $SCREENSHOT_EXISTS,
        "path": "/tmp/task_final_state.png",
        "size_bytes": $SCREENSHOT_SIZE
    }
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json

# ================================================================
# Also copy the KML file if it exists (for direct verification)
# ================================================================
if [ -f "$OUTPUT_PATH" ]; then
    cp "$OUTPUT_PATH" /tmp/output_kml.kml 2>/dev/null || true
    chmod 666 /tmp/output_kml.kml 2>/dev/null || true
    echo "KML file copied to /tmp/output_kml.kml"
fi

echo ""
echo "=== Export complete ==="