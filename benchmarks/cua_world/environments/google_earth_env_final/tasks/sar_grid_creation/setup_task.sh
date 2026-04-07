#!/bin/bash
echo "=== Setting up SAR Grid Creation task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any previous task artifacts (anti-gaming)
rm -f /home/ga/Documents/SAR_MarcusChen_Grid.kml 2>/dev/null || true
rm -f /home/ga/Documents/SAR_*.kml 2>/dev/null || true
rm -f /home/ga/Documents/SAR_*.kmz 2>/dev/null || true

# Record initial state
INITIAL_KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_KML_COUNT" > /tmp/initial_kml_count.txt

# Create initial state JSON
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_kml_count": $INITIAL_KML_COUNT,
    "expected_output": "/home/ga/Documents/SAR_MarcusChen_Grid.kml",
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
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_sar.log 2>&1 &
sleep 8

# Wait for window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Maximize and focus Google Earth window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs by pressing Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Capture initial screenshot
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
echo "============================================================"
echo "TASK: Create Search and Rescue Grid for Missing Hiker"
echo "============================================================"
echo ""
echo "SCENARIO: Hiker Marcus Chen is missing near Yosemite Valley"
echo ""
echo "TARGET COORDINATES: 37.7436, -119.5919"
echo "LOCATION: Yosemite Valley Day-Use Parking"
echo ""
echo "REQUIRED OUTPUT: /home/ga/Documents/SAR_MarcusChen_Grid.kml"
echo ""
echo "============================================================"
echo "=== Task setup complete ==="