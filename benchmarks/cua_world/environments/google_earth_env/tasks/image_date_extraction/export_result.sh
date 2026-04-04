#!/bin/bash
set -e
echo "=== Exporting image_date_extraction task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task end time: $TASK_END"
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot FIRST (before any other operations)
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
else
    FINAL_SCREENSHOT_SIZE="0"
    echo "WARNING: Could not capture final screenshot"
fi

# ================================================================
# CHECK OUTPUT FILE
# ================================================================
OUTPUT_PATH="/home/ga/imagery_date_report.txt"

OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
OUTPUT_CONTENT=""
FILE_CREATED_DURING_TASK="false"
FILE_MODIFIED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_CONTENT=$(cat "$OUTPUT_PATH" 2>/dev/null | head -c 2000 || echo "")
    
    # Check if file was created/modified during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        FILE_MODIFIED_DURING_TASK="true"
    fi
    
    echo "Output file found:"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $OUTPUT_MTIME"
    echo "  Created during task: $FILE_CREATED_DURING_TASK"
    echo ""
    echo "Content preview:"
    echo "----------------------------------------"
    head -20 "$OUTPUT_PATH" 2>/dev/null || true
    echo "----------------------------------------"
else
    echo "Output file NOT found at $OUTPUT_PATH"
fi

# ================================================================
# CHECK GOOGLE EARTH STATE
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

echo ""
echo "Google Earth state:"
echo "  Running: $GE_RUNNING"
echo "  Window title: $GE_WINDOW_TITLE"

# ================================================================
# EXTRACT CONTENT FIELDS (for verification)
# ================================================================

# Try to extract key fields from the output file
CONTAINS_LOCATION="false"
CONTAINS_COORDINATES="false"
CONTAINS_DATE="false"
CONTAINS_ALTITUDE="false"
EXTRACTED_DATE=""
EXTRACTED_LAT=""
EXTRACTED_LON=""

if [ "$OUTPUT_EXISTS" = "true" ]; then
    CONTENT_LOWER=$(echo "$OUTPUT_CONTENT" | tr '[:upper:]' '[:lower:]')
    
    # Check for location mentions
    if echo "$CONTENT_LOWER" | grep -qE "(colosseum|coliseum|colosseo|rome|roma)"; then
        CONTAINS_LOCATION="true"
    fi
    
    # Check for coordinate patterns
    if echo "$OUTPUT_CONTENT" | grep -qE "[0-9]+\.?[0-9]*°?\s*[NSns]"; then
        CONTAINS_COORDINATES="true"
    fi
    if echo "$OUTPUT_CONTENT" | grep -qE "[0-9]+\.?[0-9]*°?\s*[EWew]"; then
        CONTAINS_COORDINATES="true"
    fi
    
    # Check for date patterns
    if echo "$OUTPUT_CONTENT" | grep -qE "[0-9]{4}[-/][0-9]{1,2}[-/][0-9]{1,2}"; then
        CONTAINS_DATE="true"
        EXTRACTED_DATE=$(echo "$OUTPUT_CONTENT" | grep -oE "[0-9]{4}[-/][0-9]{1,2}[-/][0-9]{1,2}" | head -1)
    elif echo "$OUTPUT_CONTENT" | grep -qE "(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+[0-9]+,?\s+[0-9]{4}"; then
        CONTAINS_DATE="true"
        EXTRACTED_DATE=$(echo "$OUTPUT_CONTENT" | grep -oE "(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+[0-9]+,?\s+[0-9]{4}" | head -1)
    elif echo "$OUTPUT_CONTENT" | grep -qE "[0-9]{1,2}[-/][0-9]{1,2}[-/][0-9]{4}"; then
        CONTAINS_DATE="true"
        EXTRACTED_DATE=$(echo "$OUTPUT_CONTENT" | grep -oE "[0-9]{1,2}[-/][0-9]{1,2}[-/][0-9]{4}" | head -1)
    fi
    
    # Check for altitude mentions
    if echo "$CONTENT_LOWER" | grep -qE "(altitude|elevation|eye|height|[0-9]+\s*(km|m\b|ft|feet|meters))"; then
        CONTAINS_ALTITUDE="true"
    fi
    
    # Try to extract latitude (look for 41.xx pattern)
    EXTRACTED_LAT=$(echo "$OUTPUT_CONTENT" | grep -oE "41\.[0-9]+" | head -1 || echo "")
    
    # Try to extract longitude (look for 12.xx pattern)
    EXTRACTED_LON=$(echo "$OUTPUT_CONTENT" | grep -oE "12\.[0-9]+" | head -1 || echo "")
fi

echo ""
echo "Content analysis:"
echo "  Contains location: $CONTAINS_LOCATION"
echo "  Contains coordinates: $CONTAINS_COORDINATES"
echo "  Contains date: $CONTAINS_DATE"
echo "  Contains altitude: $CONTAINS_ALTITUDE"
echo "  Extracted date: $EXTRACTED_DATE"
echo "  Extracted lat: $EXTRACTED_LAT"
echo "  Extracted lon: $EXTRACTED_LON"

# ================================================================
# CREATE JSON RESULT
# ================================================================

# Escape content for JSON
ESCAPED_CONTENT=$(echo "$OUTPUT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null | sed 's/^"//;s/"$//' || echo "")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "output_content": "$ESCAPED_CONTENT",
    "contains_location": $CONTAINS_LOCATION,
    "contains_coordinates": $CONTAINS_COORDINATES,
    "contains_date": $CONTAINS_DATE,
    "contains_altitude": $CONTAINS_ALTITUDE,
    "extracted_date": "$EXTRACTED_DATE",
    "extracted_lat": "$EXTRACTED_LAT",
    "extracted_lon": "$EXTRACTED_LON",
    "google_earth_running": $GE_RUNNING,
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "final_screenshot_path": "/tmp/task_final.png",
    "final_screenshot_size": $FINAL_SCREENSHOT_SIZE
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json