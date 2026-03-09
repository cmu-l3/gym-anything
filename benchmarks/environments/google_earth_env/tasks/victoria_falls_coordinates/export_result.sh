#!/bin/bash
set -euo pipefail

echo "=== Exporting Victoria Falls Coordinates Task Result ==="

export DISPLAY=${DISPLAY:-:1}

# ============================================================
# Record task end time
# ============================================================
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task start time: $TASK_START"
echo "Task end time: $TASK_END"

# ============================================================
# Take final screenshot FIRST (for VLM verification)
# ============================================================
echo "Taking final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE=0
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
fi

# ============================================================
# Check output file
# ============================================================
OUTPUT_PATH="/home/ga/Documents/victoria_falls_coords.txt"
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
OUTPUT_MTIME=0
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "Output file was created during task"
    else
        echo "WARNING: Output file existed before task started"
    fi
    
    # Read file content (escape for JSON)
    FILE_CONTENT=$(cat "$OUTPUT_PATH" 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g' || echo "")
    echo "File content: $FILE_CONTENT"
else
    echo "Output file not found"
fi

# ============================================================
# Check if Google Earth is running
# ============================================================
GE_RUNNING="false"
GE_PID=""
if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f "google-earth" | head -1)
    echo "Google Earth is running (PID: $GE_PID)"
fi

# ============================================================
# Get window title for context
# ============================================================
WINDOW_TITLE=""
if command -v xdotool &> /dev/null; then
    WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
fi
echo "Active window: $WINDOW_TITLE"

# ============================================================
# Attempt to parse coordinates from file
# ============================================================
PARSED_LAT=""
PARSED_LON=""
PARSE_SUCCESS="false"

if [ "$OUTPUT_EXISTS" = "true" ] && [ -n "$FILE_CONTENT" ]; then
    # Try to extract coordinates using Python
    PARSE_RESULT=$(python3 << 'PYEOF'
import re
import sys

content = """FILE_CONTENT_PLACEHOLDER"""

# Try various patterns
patterns = [
    # "Latitude: -17.9243, Longitude: 25.8572"
    r'[Ll]at(?:itude)?[:\s]+(-?\d+\.?\d*)[,\s]+[Ll]on(?:gitude)?[:\s]+(-?\d+\.?\d*)',
    # "-17.9243, 25.8572" or "-17.9243 25.8572"
    r'(-?\d+\.\d{3,})[,\s]+(-?\d+\.\d{3,})',
    # "17.9243°S, 25.8572°E" or "17.9243 S, 25.8572 E"
    r'(\d+\.?\d*)[°]?\s*([SN])[,\s]+(\d+\.?\d*)[°]?\s*([EW])',
    # "S17.9243, E25.8572"
    r'([SN])\s*(-?\d+\.?\d*)[,\s]+([EW])\s*(-?\d+\.?\d*)',
]

lat, lon = None, None

for pattern in patterns:
    match = re.search(pattern, content, re.IGNORECASE)
    if match:
        groups = match.groups()
        if len(groups) == 2:
            lat, lon = float(groups[0]), float(groups[1])
            break
        elif len(groups) == 4:
            if groups[1].upper() in 'SN':
                # Pattern: number, direction, number, direction
                lat = float(groups[0])
                if groups[1].upper() == 'S':
                    lat = -lat
                lon = float(groups[2])
                if groups[3].upper() == 'W':
                    lon = -lon
            else:
                # Pattern: direction, number, direction, number
                lat = float(groups[1])
                if groups[0].upper() == 'S':
                    lat = -lat
                lon = float(groups[3])
                if groups[2].upper() == 'W':
                    lon = -lon
            break

if lat is not None and lon is not None:
    print(f"SUCCESS:{lat}:{lon}")
else:
    print("FAILED:0:0")
PYEOF
)
    
    # Replace placeholder with actual content
    PARSE_RESULT=$(echo "$PARSE_RESULT" | sed "s|FILE_CONTENT_PLACEHOLDER|$FILE_CONTENT|g")
    
    # Re-run with actual content
    PARSE_RESULT=$(python3 << PYEOF
import re

content = """$FILE_CONTENT"""

patterns = [
    r'[Ll]at(?:itude)?[:\s]+(-?\d+\.?\d*)[,\s]+[Ll]on(?:gitude)?[:\s]+(-?\d+\.?\d*)',
    r'(-?\d+\.\d{3,})[,\s]+(-?\d+\.\d{3,})',
    r'(\d+\.?\d*)[°]?\s*([SN])[,\s]+(\d+\.?\d*)[°]?\s*([EW])',
]

lat, lon = None, None

for pattern in patterns:
    match = re.search(pattern, content, re.IGNORECASE)
    if match:
        groups = match.groups()
        if len(groups) == 2:
            lat, lon = float(groups[0]), float(groups[1])
            break
        elif len(groups) == 4:
            lat = float(groups[0])
            if groups[1].upper() == 'S':
                lat = -lat
            lon = float(groups[2])
            if groups[3].upper() == 'W':
                lon = -lon
            break

if lat is not None and lon is not None:
    print(f"SUCCESS:{lat}:{lon}")
else:
    print("FAILED:0:0")
PYEOF
)
    
    if echo "$PARSE_RESULT" | grep -q "^SUCCESS:"; then
        PARSE_SUCCESS="true"
        PARSED_LAT=$(echo "$PARSE_RESULT" | cut -d: -f2)
        PARSED_LON=$(echo "$PARSE_RESULT" | cut -d: -f3)
        echo "Parsed coordinates: Lat=$PARSED_LAT, Lon=$PARSED_LON"
    else
        echo "Failed to parse coordinates from file content"
    fi
fi

# ============================================================
# Create JSON result file
# ============================================================
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
    "file_content": "$FILE_CONTENT",
    "parse_success": $PARSE_SUCCESS,
    "parsed_latitude": ${PARSED_LAT:-null},
    "parsed_longitude": ${PARSED_LON:-null},
    "google_earth_running": $GE_RUNNING,
    "google_earth_pid": "${GE_PID:-}",
    "window_title": "$WINDOW_TITLE",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_bytes": $SCREENSHOT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Task Result Summary ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="