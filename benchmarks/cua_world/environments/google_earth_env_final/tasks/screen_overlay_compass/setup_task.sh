#!/bin/bash
echo "=== Setting up screen_overlay_compass task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure X server access
xhost +local: 2>/dev/null || true

# Create output directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up any previous task artifacts
rm -f /home/ga/Documents/compass_overlay.kml 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record initial state
INITIAL_KML_EXISTS="false"
if [ -f "/home/ga/Documents/compass_overlay.kml" ]; then
    INITIAL_KML_EXISTS="true"
fi

cat > /tmp/initial_state.json << EOF
{
    "kml_exists": $INITIAL_KML_EXISTS,
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Give additional time for full initialization
sleep 5

# Dismiss any startup dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Try to dismiss "Start-up Tips" if present
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# Maximize the Google Earth window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the Google Earth window
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Take initial screenshot
mkdir -p /tmp/task_screenshots
DISPLAY=:1 scrot /tmp/task_screenshots/initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_screenshots/initial_state.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_screenshots/initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_screenshots/initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Check if Google Earth is running
if pgrep -f google-earth-pro > /dev/null; then
    echo "Google Earth Pro is running"
else
    echo "WARNING: Google Earth Pro may not have started properly"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Create a Screen Overlay with Compass Rose"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Go to Add > Screen Overlay (NOT Image Overlay!)"
echo "2. Name it: Compass Legend"
echo "3. Set the image link to the Wikipedia compass rose image"
echo "4. Position it in bottom-right corner (Screen X=0.95, Y=0.05, Fraction)"
echo "5. Save as KML to: /home/ga/Documents/compass_overlay.kml"
echo ""
echo "IMPORTANT: Screen Overlay stays fixed on screen during navigation"
echo "           Image Overlay is georeferenced and moves with the Earth"
echo "============================================================"