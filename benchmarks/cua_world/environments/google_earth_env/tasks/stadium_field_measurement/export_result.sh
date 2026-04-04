#!/bin/bash
set -e
echo "=== Exporting Stadium Field Measurement task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task timing: Start=$TASK_START, End=$TASK_END"

# Take final screenshot FIRST (before any other operations)
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE="0"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
fi

# ================================================================
# CHECK KML OUTPUT FILE
# ================================================================
KML_PATH="/home/ga/Documents/camp_nou_survey.kml"
KML_EXISTS="false"
KML_SIZE="0"
KML_MTIME="0"
KML_CREATED_DURING_TASK="false"
KML_CONTENT=""

if [ -f "$KML_PATH" ]; then
    KML_EXISTS="true"
    KML_SIZE=$(stat -c %s "$KML_PATH" 2>/dev/null || echo "0")
    KML_MTIME=$(stat -c %Y "$KML_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$KML_MTIME" -gt "$TASK_START" ]; then
        KML_CREATED_DURING_TASK="true"
    fi
    
    # Read KML content (first 5000 chars)
    KML_CONTENT=$(head -c 5000 "$KML_PATH" 2>/dev/null | base64 -w 0 || echo "")
    
    echo "KML file found: size=$KML_SIZE, mtime=$KML_MTIME, created_during_task=$KML_CREATED_DURING_TASK"
fi

# ================================================================
# CHECK TEXT OUTPUT FILE
# ================================================================
TXT_PATH="/home/ga/Documents/field_measurements.txt"
TXT_EXISTS="false"
TXT_SIZE="0"
TXT_MTIME="0"
TXT_CREATED_DURING_TASK="false"
TXT_CONTENT=""
MEASURED_LENGTH=""
MEASURED_WIDTH=""
FIFA_COMPLIANT=""

if [ -f "$TXT_PATH" ]; then
    TXT_EXISTS="true"
    TXT_SIZE=$(stat -c %s "$TXT_PATH" 2>/dev/null || echo "0")
    TXT_MTIME=$(stat -c %Y "$TXT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$TXT_MTIME" -gt "$TASK_START" ]; then
        TXT_CREATED_DURING_TASK="true"
    fi
    
    # Read text content
    TXT_CONTENT=$(cat "$TXT_PATH" 2>/dev/null || echo "")
    
    # Parse measurements using grep/sed
    MEASURED_LENGTH=$(echo "$TXT_CONTENT" | grep -i "length" | grep -oE "[0-9]+\.?[0-9]*" | head -1 || echo "")
    MEASURED_WIDTH=$(echo "$TXT_CONTENT" | grep -i "width" | grep -oE "[0-9]+\.?[0-9]*" | head -1 || echo "")
    FIFA_COMPLIANT=$(echo "$TXT_CONTENT" | grep -i "fifa" | grep -ioE "(yes|no)" | head -1 || echo "")
    
    echo "TXT file found: size=$TXT_SIZE, mtime=$TXT_MTIME, created_during_task=$TXT_CREATED_DURING_TASK"
    echo "Parsed measurements: length=$MEASURED_LENGTH, width=$MEASURED_WIDTH, fifa=$FIFA_COMPLIANT"
fi

# ================================================================
# CHECK GOOGLE EARTH STATE
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

GE_WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")

echo "Google Earth running: $GE_RUNNING"
echo "Window title: $GE_WINDOW_TITLE"

# ================================================================
# CREATE JSON RESULT
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Escape the TXT content for JSON
TXT_CONTENT_ESCAPED=$(echo "$TXT_CONTENT" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    
    "kml_file": {
        "exists": $KML_EXISTS,
        "size_bytes": $KML_SIZE,
        "mtime": $KML_MTIME,
        "created_during_task": $KML_CREATED_DURING_TASK,
        "content_base64": "$KML_CONTENT"
    },
    
    "text_file": {
        "exists": $TXT_EXISTS,
        "size_bytes": $TXT_SIZE,
        "mtime": $TXT_MTIME,
        "created_during_task": $TXT_CREATED_DURING_TASK,
        "content": $TXT_CONTENT_ESCAPED,
        "measured_length": "$MEASURED_LENGTH",
        "measured_width": "$MEASURED_WIDTH",
        "fifa_compliant": "$FIFA_COMPLIANT"
    },
    
    "google_earth": {
        "running": $GE_RUNNING,
        "window_title": "$GE_WINDOW_TITLE"
    },
    
    "screenshot": {
        "exists": $SCREENSHOT_EXISTS,
        "size_bytes": $SCREENSHOT_SIZE,
        "path": "/tmp/task_final.png"
    }
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json