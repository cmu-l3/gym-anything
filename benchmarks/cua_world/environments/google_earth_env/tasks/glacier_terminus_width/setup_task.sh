#!/bin/bash
set -euo pipefail

echo "=== Setting up glacier_terminus_width task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create output directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing output file (prevents pre-prepared files)
rm -f /home/ga/Documents/glacier_terminus.kml 2>/dev/null || true

# Record initial state - check if output exists
if [ -f "/home/ga/Documents/glacier_terminus.kml" ]; then
    INITIAL_EXISTS="true"
    INITIAL_SIZE=$(stat -c%s "/home/ga/Documents/glacier_terminus.kml" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c%Y "/home/ga/Documents/glacier_terminus.kml" 2>/dev/null || echo "0")
else
    INITIAL_EXISTS="false"
    INITIAL_SIZE="0"
    INITIAL_MTIME="0"
fi

# Save initial state for verification
cat > /tmp/initial_state.json << EOF
{
    "output_exists": $INITIAL_EXISTS,
    "output_size": $INITIAL_SIZE,
    "output_mtime": $INITIAL_MTIME,
    "task_start_time": $(date +%s),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Google Earth instances for clean start
echo "Killing any existing Google Earth instances..."
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i}s"
        break
    fi
    sleep 1
done

# Get window ID
WINDOW_ID=$(wmctrl -l | grep -i "Google Earth" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    echo "Window ID: $WINDOW_ID"
    
    # Maximize the window
    wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Focus the window
    wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    sleep 1
else
    echo "WARNING: Could not find Google Earth window ID"
fi

# Dismiss any startup dialogs by pressing Escape
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state screenshot..."
sleep 2
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
echo "TASK: Measure Perito Moreno Glacier Terminus Width"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to Perito Moreno Glacier, Argentina"
echo "   (Search: 'Perito Moreno Glacier' or coords: -50.497, -73.137)"
echo ""
echo "2. Use the Path tool (Add > Path) to trace the terminus"
echo "   - Follow the ice/water boundary from south to north"
echo "   - Name it: 'Perito_Moreno_Terminus'"
echo ""
echo "3. Create a placemark at the terminus center"
echo "   - Name it: 'Terminus_Center'"
echo "   - Add the width measurement to the description"
echo ""
echo "4. Export to: ~/Documents/glacier_terminus.kml"
echo ""
echo "Expected terminus width: ~5 km (range: 4-6 km)"
echo "============================================================"