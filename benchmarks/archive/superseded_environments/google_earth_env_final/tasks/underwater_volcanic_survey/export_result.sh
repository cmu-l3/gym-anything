#!/bin/bash
set -e
echo "=== Exporting Underwater Volcanic Survey task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
FINAL_SCREENSHOT="/tmp/task_final_screenshot.png"
scrot "$FINAL_SCREENSHOT" 2>/dev/null || true
if [ -f "$FINAL_SCREENSHOT" ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s "$FINAL_SCREENSHOT" 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
else
    FINAL_SCREENSHOT_SIZE="0"
    echo "WARNING: Could not capture final screenshot"
fi

# ============================================================
# Check output screenshot file
# ============================================================
OUTPUT_PATH="/home/ga/Documents/axial_seamount_survey.png"
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
        echo "Output file created during task: YES"
    else
        echo "Output file created during task: NO (predates task start)"
    fi
    echo "Output file size: $OUTPUT_SIZE bytes"
else
    echo "Output file NOT found at $OUTPUT_PATH"
fi

# ============================================================
# Check placemark in myplaces.kml
# ============================================================
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"
MYPLACES_ALT="/home/ga/.config/Google/googleearth/myplaces.kml"
PLACEMARK_FOUND="false"
PLACEMARK_NAME=""
PLACEMARK_COORDS=""
PLACEMARK_DESCRIPTION=""
FINAL_PLACEMARK_COUNT="0"

for KML_FILE in "$MYPLACES_FILE" "$MYPLACES_ALT"; do
    if [ -f "$KML_FILE" ]; then
        FINAL_PLACEMARK_COUNT=$(grep -c "<Placemark>" "$KML_FILE" 2>/dev/null || echo "0")
        
        # Check for Axial Seamount placemark
        if grep -qi "Axial Seamount" "$KML_FILE" 2>/dev/null; then
            PLACEMARK_FOUND="true"
            
            # Extract placemark details using Python for reliable parsing
            PLACEMARK_INFO=$(python3 << 'PYEOF'
import re
import sys

kml_files = ["/home/ga/.googleearth/myplaces.kml", "/home/ga/.config/Google/googleearth/myplaces.kml"]
for kml_file in kml_files:
    try:
        with open(kml_file, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        # Find Axial Seamount placemark
        pattern = r'<Placemark>.*?<name>([^<]*Axial[^<]*)</name>.*?</Placemark>'
        match = re.search(pattern, content, re.DOTALL | re.IGNORECASE)
        
        if match:
            placemark_block = match.group(0)
            name = match.group(1)
            
            # Extract coordinates
            coords_match = re.search(r'<coordinates>([^<]+)</coordinates>', placemark_block)
            coords = coords_match.group(1).strip() if coords_match else ""
            
            # Extract description
            desc_match = re.search(r'<description>([^<]*)</description>', placemark_block)
            description = desc_match.group(1) if desc_match else ""
            
            print(f"NAME:{name}")
            print(f"COORDS:{coords}")
            print(f"DESC:{description}")
            sys.exit(0)
    except:
        pass
print("NAME:")
print("COORDS:")
print("DESC:")
PYEOF
)
            PLACEMARK_NAME=$(echo "$PLACEMARK_INFO" | grep "^NAME:" | cut -d: -f2-)
            PLACEMARK_COORDS=$(echo "$PLACEMARK_INFO" | grep "^COORDS:" | cut -d: -f2-)
            PLACEMARK_DESCRIPTION=$(echo "$PLACEMARK_INFO" | grep "^DESC:" | cut -d: -f2-)
            
            echo "Placemark found: $PLACEMARK_NAME"
            echo "Placemark coordinates: $PLACEMARK_COORDS"
            echo "Placemark description: $PLACEMARK_DESCRIPTION"
        fi
        break
    fi
done

INITIAL_PLACEMARK_COUNT=$(cat /tmp/initial_placemark_count.txt 2>/dev/null || echo "0")
PLACEMARK_ADDED="false"
if [ "$FINAL_PLACEMARK_COUNT" -gt "$INITIAL_PLACEMARK_COUNT" ]; then
    PLACEMARK_ADDED="true"
fi

# ============================================================
# Check if Google Earth is still running
# ============================================================
GE_RUNNING="false"
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Get window title
WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_screenshot": {
        "path": "$OUTPUT_PATH",
        "exists": $OUTPUT_EXISTS,
        "size_bytes": $OUTPUT_SIZE,
        "mtime": $OUTPUT_MTIME,
        "created_during_task": $FILE_CREATED_DURING_TASK
    },
    "placemark": {
        "found": $PLACEMARK_FOUND,
        "name": "$PLACEMARK_NAME",
        "coordinates": "$PLACEMARK_COORDS",
        "description": "$PLACEMARK_DESCRIPTION",
        "added_during_task": $PLACEMARK_ADDED
    },
    "placemark_counts": {
        "initial": $INITIAL_PLACEMARK_COUNT,
        "final": $FINAL_PLACEMARK_COUNT
    },
    "google_earth_running": $GE_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "final_screenshot_path": "$FINAL_SCREENSHOT",
    "final_screenshot_size": $FINAL_SCREENSHOT_SIZE
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="