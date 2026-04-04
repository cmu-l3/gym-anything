#!/bin/bash
set -e
echo "=== Setting up floorplan_gis_overlay task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/LibreCAD

# ============================================================
# Prepare Data
# ============================================================
ORIGINAL_FILE="/home/ga/Documents/LibreCAD/floorplan.dxf"
SAMPLE_SOURCE="/opt/librecad_samples/floorplan.dxf"

# Ensure the floorplan exists
if [ ! -f "$ORIGINAL_FILE" ]; then
    if [ -f "$SAMPLE_SOURCE" ]; then
        echo "Copying sample floorplan to workspace..."
        cp "$SAMPLE_SOURCE" "$ORIGINAL_FILE"
    else
        echo "ERROR: Sample floorplan not found at $SAMPLE_SOURCE"
        exit 1
    fi
fi

# Set permissions
chown ga:ga "$ORIGINAL_FILE"

# Record initial file hash and size for verification
md5sum "$ORIGINAL_FILE" > /tmp/initial_file_hash.txt
stat -c%s "$ORIGINAL_FILE" > /tmp/initial_file_size.txt

# Clean up previous output
rm -f /home/ga/Documents/LibreCAD/floorplan_gis.dxf

# ============================================================
# Start Application
# ============================================================
# Kill any existing instances
pkill -f librecad 2>/dev/null || true
sleep 2

echo "Starting LibreCAD with floorplan..."
# Launch LibreCAD opening the specific file
su - ga -c "DISPLAY=:1 librecad '$ORIGINAL_FILE' > /tmp/librecad.log 2>&1 &"

# Wait for window to appear
echo "Waiting for LibreCAD window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Maximize window
echo "Maximizing window..."
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# Allow time for file to fully load and render
sleep 5

# Dismiss any potential "Tip of the Day" or startup dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="