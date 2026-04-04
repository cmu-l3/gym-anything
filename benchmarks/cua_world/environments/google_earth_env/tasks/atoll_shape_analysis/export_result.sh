#!/bin/bash
echo "=== Exporting Bora Bora Shape Analysis task result ==="

export DISPLAY=${DISPLAY:-:1}

# ================================================================
# Record task end time
# ================================================================
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# ================================================================
# Capture final screenshot FIRST (for evidence)
# ================================================================
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_final_screenshot.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
fi

# ================================================================
# Check output file
# ================================================================
OUTPUT_PATH="/home/ga/bora_bora_shape_analysis.txt"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_CONTENT=$(cat "$OUTPUT_PATH" 2>/dev/null || echo "")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Parse measurements from file
    AREA_VALUE=$(grep -oP 'Area:\s*[\d.]+' "$OUTPUT_PATH" 2>/dev/null | grep -oP '[\d.]+' || echo "0")
    PERIMETER_VALUE=$(grep -oP 'Perimeter:\s*[\d.]+' "$OUTPUT_PATH" 2>/dev/null | grep -oP '[\d.]+' || echo "0")
    PP_SCORE_VALUE=$(grep -oP '(?:Polsby|Score).*?[\d.]+' "$OUTPUT_PATH" 2>/dev/null | grep -oP '[\d.]+$' || echo "0")
    
    echo "Output file found:"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $OUTPUT_MTIME"
    echo "  Created during task: $FILE_CREATED_DURING_TASK"
    echo "  Area: $AREA_VALUE"
    echo "  Perimeter: $PERIMETER_VALUE"
    echo "  PP Score: $PP_SCORE_VALUE"
    echo ""
    echo "File contents:"
    cat "$OUTPUT_PATH"
    echo ""
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    OUTPUT_CONTENT=""
    FILE_CREATED_DURING_TASK="false"
    AREA_VALUE="0"
    PERIMETER_VALUE="0"
    PP_SCORE_VALUE="0"
    echo "Output file NOT found at $OUTPUT_PATH"
fi

# ================================================================
# Check My Places for saved polygon
# ================================================================
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
POLYGON_SAVED="false"
POLYGON_NAME_CORRECT="false"

if [ -f "$MYPLACES_PATH" ]; then
    MYPLACES_EXISTS="true"
    MYPLACES_SIZE=$(stat -c %s "$MYPLACES_PATH" 2>/dev/null || echo "0")
    MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_PATH" 2>/dev/null || echo "0")
    
    # Check initial state
    INITIAL_MYPLACES_MTIME=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('myplaces_mtime', 0))" 2>/dev/null || echo "0")
    
    if [ "$MYPLACES_MTIME" -gt "$INITIAL_MYPLACES_MTIME" ]; then
        MYPLACES_MODIFIED="true"
    else
        MYPLACES_MODIFIED="false"
    fi
    
    # Check for Bora Bora polygon
    if grep -qi "bora" "$MYPLACES_PATH" 2>/dev/null; then
        POLYGON_SAVED="true"
        
        # Check for correct name
        if grep -qi "Bora Bora Main Island" "$MYPLACES_PATH" 2>/dev/null; then
            POLYGON_NAME_CORRECT="true"
        fi
        
        # Check for polygon element
        if grep -qi "<Polygon>" "$MYPLACES_PATH" 2>/dev/null; then
            HAS_POLYGON_ELEMENT="true"
        else
            HAS_POLYGON_ELEMENT="false"
        fi
    fi
    
    echo "My Places file:"
    echo "  Size: $MYPLACES_SIZE bytes"
    echo "  Modified: $MYPLACES_MTIME"
    echo "  Modified during task: $MYPLACES_MODIFIED"
    echo "  Bora Bora entry found: $POLYGON_SAVED"
    echo "  Correct name: $POLYGON_NAME_CORRECT"
else
    MYPLACES_EXISTS="false"
    MYPLACES_SIZE="0"
    MYPLACES_MTIME="0"
    MYPLACES_MODIFIED="false"
    HAS_POLYGON_ELEMENT="false"
    echo "My Places file not found"
fi

# ================================================================
# Check Google Earth is still running
# ================================================================
if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f "google-earth" | head -1)
    echo "Google Earth is running (PID: $GE_PID)"
else
    GE_RUNNING="false"
    echo "Google Earth is NOT running"
fi

# ================================================================
# Get window information
# ================================================================
WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
GE_WINDOW_TITLE=""
if echo "$WINDOW_LIST" | grep -qi "Google Earth"; then
    GE_WINDOW_TITLE=$(echo "$WINDOW_LIST" | grep -i "Google Earth" | head -1 | cut -d' ' -f5-)
fi

# ================================================================
# Create result JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    
    "output_file": {
        "exists": $OUTPUT_EXISTS,
        "size_bytes": $OUTPUT_SIZE,
        "mtime": $OUTPUT_MTIME,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "content": $(echo "$OUTPUT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
    },
    
    "measurements": {
        "area_sq_km": $AREA_VALUE,
        "perimeter_km": $PERIMETER_VALUE,
        "polsby_popper_score": $PP_SCORE_VALUE
    },
    
    "myplaces": {
        "exists": $MYPLACES_EXISTS,
        "size_bytes": ${MYPLACES_SIZE:-0},
        "mtime": ${MYPLACES_MTIME:-0},
        "modified_during_task": ${MYPLACES_MODIFIED:-false},
        "polygon_saved": $POLYGON_SAVED,
        "polygon_name_correct": $POLYGON_NAME_CORRECT,
        "has_polygon_element": ${HAS_POLYGON_ELEMENT:-false}
    },
    
    "google_earth": {
        "running": $GE_RUNNING,
        "window_title": $(echo "$GE_WINDOW_TITLE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null || echo '""')
    },
    
    "screenshots": {
        "final_exists": $SCREENSHOT_EXISTS,
        "final_path": "/tmp/task_final_screenshot.png"
    }
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Also copy the output file to /tmp for easier access
if [ -f "$OUTPUT_PATH" ]; then
    cp "$OUTPUT_PATH" /tmp/bora_bora_output.txt 2>/dev/null || true
    chmod 666 /tmp/bora_bora_output.txt 2>/dev/null || true
fi

# Copy myplaces.kml for verification
if [ -f "$MYPLACES_PATH" ]; then
    cp "$MYPLACES_PATH" /tmp/myplaces_export.kml 2>/dev/null || true
    chmod 666 /tmp/myplaces_export.kml 2>/dev/null || true
fi

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json