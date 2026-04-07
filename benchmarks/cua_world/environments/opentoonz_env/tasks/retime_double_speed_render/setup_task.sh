#!/bin/bash
echo "=== Setting up retime_double_speed_render task ==="

SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/double_speed"

# 1. Ensure output directory exists and is clean
echo "Cleaning output directory..."
su - ga -c "mkdir -p $OUTPUT_DIR"
find "$OUTPUT_DIR" -maxdepth 1 -type f -delete 2>/dev/null || true

# 2. Verify source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Try to copy from backup/templates if available, or fail
    if [ -f "/usr/share/opentoonz/stuff/projects/samples/scenes/dwanko_run.tnz" ]; then
        cp "/usr/share/opentoonz/stuff/projects/samples/scenes/dwanko_run.tnz" "$SOURCE_SCENE"
    else
        exit 1
    fi
fi
echo "Source scene verified: $SOURCE_SCENE"

# 3. Analyze original frame count (CRITICAL for verification)
# We parse the .tnz XML to find the maximum row index used in the xsheet
echo "Analyzing original scene duration..."
ORIGINAL_FRAME_COUNT=$(python3 -c "
import xml.etree.ElementTree as ET
import sys

try:
    tree = ET.parse('$SOURCE_SCENE')
    root = tree.getroot()
    max_row = 0
    found_cells = False
    
    # Iterate over all cells in the xsheet
    for cell in root.findall('.//cell'):
        found_cells = True
        row = int(cell.get('row', -1))
        if row > max_row:
            max_row = row
            
    # Frame count is max_index + 1
    if found_cells:
        print(max_row + 1)
    else:
        print(0)
except Exception as e:
    print(0)
")

# Fallback if parsing fails (dwanko_run is typically around 11-13 frames, but usually looped longer in xsheet)
# If 0, we might assume a default or mark as unknown
if [ "$ORIGINAL_FRAME_COUNT" -eq "0" ]; then
    echo "Warning: Could not determine frame count, assuming default of 13"
    ORIGINAL_FRAME_COUNT=13
fi

echo "$ORIGINAL_FRAME_COUNT" > /tmp/original_frame_count.txt
echo "Original frame count determined: $ORIGINAL_FRAME_COUNT"

# 4. Record task start timestamp
date +%s > /tmp/task_start_timestamp

# 5. Launch OpenToonz
# Ensure clean state by killing existing instances
pkill -f opentoonz 2>/dev/null || true
sleep 1

echo "Launching OpenToonz..."
# Use launcher script or direct command
if [ -x /usr/local/bin/launch-opentoonz ]; then
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
else
    su - ga -c "DISPLAY=:1 opentoonz &"
fi

# Wait for window
echo "Waiting for OpenToonz window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 6. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="