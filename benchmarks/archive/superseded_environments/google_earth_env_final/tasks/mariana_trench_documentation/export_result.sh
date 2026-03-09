#!/bin/bash
set -e
echo "=== Exporting Mariana Trench Documentation Task Result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task timing: Start=$TASK_START, End=$TASK_END"

# Take final screenshot FIRST (before any state changes)
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE="0"
if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
fi

# ================================================================
# Check output KML file
# ================================================================
OUTPUT_PATH="/home/ga/Documents/challenger_deep.kml"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "KML file was created during task execution"
    else
        echo "WARNING: KML file exists but was NOT created during task"
    fi
    
    echo "KML file found: ${OUTPUT_SIZE} bytes, mtime=${OUTPUT_MTIME}"
else
    echo "KML file NOT found at expected path"
fi

# Also check for KMZ (compressed KML)
KMZ_PATH="/home/ga/Documents/challenger_deep.kmz"
KMZ_EXISTS="false"
if [ -f "$KMZ_PATH" ]; then
    KMZ_EXISTS="true"
    echo "Note: KMZ file also found (compressed format)"
fi

# ================================================================
# Check Google Earth state
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | sed 's/^[^ ]* *[^ ]* *[^ ]* *//')
fi

echo "Google Earth running: $GE_RUNNING"
echo "Window title: $GE_WINDOW_TITLE"

# ================================================================
# Check My Places for the placemark
# ================================================================
MYPLACES_HAS_CHALLENGER="false"
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"

if [ -f "$MYPLACES_PATH" ]; then
    if grep -qi "challenger" "$MYPLACES_PATH" 2>/dev/null; then
        MYPLACES_HAS_CHALLENGER="true"
        echo "Found 'challenger' reference in myplaces.kml"
    fi
fi

# ================================================================
# Parse KML content if it exists
# ================================================================
KML_VALID="false"
KML_PLACEMARK_NAME=""
KML_COORDINATES=""
KML_DESCRIPTION=""
KML_HAS_DEPTH="false"
KML_HAS_MARIANA="false"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    # Try to extract placemark name
    KML_PLACEMARK_NAME=$(grep -oP '(?<=<name>)[^<]+' "$OUTPUT_PATH" 2>/dev/null | head -1 || echo "")
    
    # Try to extract coordinates
    KML_COORDINATES=$(grep -oP '(?<=<coordinates>)[^<]+' "$OUTPUT_PATH" 2>/dev/null | head -1 || echo "")
    
    # Try to extract description
    KML_DESCRIPTION=$(grep -oP '(?<=<description>)[^<]+' "$OUTPUT_PATH" 2>/dev/null | head -1 || echo "")
    
    # Also try CDATA wrapped description
    if [ -z "$KML_DESCRIPTION" ]; then
        KML_DESCRIPTION=$(grep -oP '(?<=<description><!\[CDATA\[)[^\]]+' "$OUTPUT_PATH" 2>/dev/null | head -1 || echo "")
    fi
    
    # Check for valid KML structure
    if grep -q "<kml" "$OUTPUT_PATH" 2>/dev/null && grep -q "<Placemark" "$OUTPUT_PATH" 2>/dev/null; then
        KML_VALID="true"
    fi
    
    # Check for depth mention in description (negative number in range)
    if echo "$KML_DESCRIPTION" | grep -qE '(-1[01][0-9]{3}|10[0-9]{3}|11[0-9]{3})' 2>/dev/null; then
        KML_HAS_DEPTH="true"
    fi
    
    # Check for mariana mention
    if echo "$KML_DESCRIPTION" | grep -qi "mariana" 2>/dev/null; then
        KML_HAS_MARIANA="true"
    fi
    
    echo "KML parsing results:"
    echo "  Valid structure: $KML_VALID"
    echo "  Placemark name: $KML_PLACEMARK_NAME"
    echo "  Coordinates: $KML_COORDINATES"
    echo "  Has depth: $KML_HAS_DEPTH"
    echo "  Has Mariana ref: $KML_HAS_MARIANA"
fi

# ================================================================
# Create comprehensive result JSON
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
        "kmz_exists": $KMZ_EXISTS
    },
    
    "kml_content": {
        "valid_structure": $KML_VALID,
        "placemark_name": "$KML_PLACEMARK_NAME",
        "coordinates": "$KML_COORDINATES",
        "description": "$(echo "$KML_DESCRIPTION" | head -c 500 | tr '\n' ' ' | sed 's/"/\\"/g')",
        "has_depth_value": $KML_HAS_DEPTH,
        "has_mariana_reference": $KML_HAS_MARIANA
    },
    
    "google_earth_state": {
        "running": $GE_RUNNING,
        "window_title": "$GE_WINDOW_TITLE",
        "myplaces_has_challenger": $MYPLACES_HAS_CHALLENGER
    },
    
    "screenshot": {
        "exists": $SCREENSHOT_EXISTS,
        "size_bytes": $SCREENSHOT_SIZE,
        "path": "/tmp/task_final_state.png"
    }
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json