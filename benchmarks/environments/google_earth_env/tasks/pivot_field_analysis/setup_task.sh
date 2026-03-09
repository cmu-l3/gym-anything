#!/bin/bash
echo "=== Setting up Center Pivot Irrigation Assessment task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists and is clean
sudo -u ga mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any previous task output (clean slate)
rm -f /home/ga/Documents/irrigation_pivot.kml 2>/dev/null || true
rm -f /home/ga/Documents/irrigation_pivot.kmz 2>/dev/null || true

# Record initial state - no KML file should exist
if [ -f "/home/ga/Documents/irrigation_pivot.kml" ] || [ -f "/home/ga/Documents/irrigation_pivot.kmz" ]; then
    echo "true" > /tmp/initial_kml_exists.txt
else
    echo "false" > /tmp/initial_kml_exists.txt
fi
echo "Initial KML exists: $(cat /tmp/initial_kml_exists.txt)"

# Count existing files in Documents for reference
INITIAL_DOC_COUNT=$(ls -1 /home/ga/Documents/*.kml /home/ga/Documents/*.kmz 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_DOC_COUNT" > /tmp/initial_kml_count.txt

# Ensure Google Earth Pro is installed
if ! command -v google-earth-pro &> /dev/null; then
    echo "ERROR: Google Earth Pro not installed"
    exit 1
fi

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 2
done

# Additional wait for full initialization (imagery loading, etc.)
sleep 10

# Maximize and focus window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Try to dismiss any startup dialogs/tips with Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Verify Google Earth is running
if pgrep -f google-earth-pro > /dev/null; then
    echo "Google Earth Pro is running"
    GE_RUNNING="true"
else
    echo "WARNING: Google Earth Pro may not be running"
    GE_RUNNING="false"
fi
echo "$GE_RUNNING" > /tmp/ge_running_at_start.txt

# Take screenshot of initial state (for evidence)
echo "Capturing initial state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Center Pivot Irrigation Assessment"
echo "============================================================"
echo ""
echo "Navigate to coordinates: 37.9583, -100.6425 (Kansas)"
echo "Measure the diameter of the circular irrigation field"
echo "Create a placemark named 'Pivot Field KC-2847' at the center"
echo "Include the diameter measurement in the description"
echo "Save to: ~/Documents/irrigation_pivot.kml"
echo ""
echo "Expected diameter: ~800-850 meters"
echo "============================================================"