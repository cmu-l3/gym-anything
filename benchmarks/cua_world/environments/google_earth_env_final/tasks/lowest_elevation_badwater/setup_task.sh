#!/bin/bash
set -e
echo "=== Setting up Badwater Basin elevation documentation task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Create output directory and ensure clean state
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any existing output file (clean state)
rm -f /home/ga/Documents/badwater_basin.kml
rm -f /home/ga/Documents/*.kml 2>/dev/null || true

# Record initial state
INITIAL_KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_KML_COUNT" > /tmp/initial_kml_count.txt

# Store ground truth for verification (hidden from agent)
mkdir -p /var/lib/ground_truth
chmod 700 /var/lib/ground_truth
cat > /var/lib/ground_truth/badwater_expected.json << 'EOF'
{
  "target_name": "Badwater Basin",
  "latitude": 36.2291,
  "longitude": -116.7677,
  "coordinate_tolerance": 0.02,
  "elevation_meters": -86,
  "elevation_feet": -282,
  "elevation_tolerance_m": 15,
  "region": "Death Valley, California",
  "designation": "Lowest point in North America"
}
EOF
chmod 600 /var/lib/ground_truth/badwater_expected.json

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after $i seconds"
        break
    fi
    sleep 2
done

# Allow additional time for initial globe loading and imagery
echo "Waiting for globe to load..."
sleep 10

# Maximize and focus window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs/tips with Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
echo "Capturing initial state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Record initial state JSON
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_kml_count": $INITIAL_KML_COUNT,
    "google_earth_started": true,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Document Badwater Basin Elevation"
echo "============================================================"
echo ""
echo "Badwater Basin in Death Valley is the lowest point in"
echo "North America at -86 meters (-282 feet) below sea level."
echo ""
echo "Your task:"
echo "1. Search for 'Badwater Basin, Death Valley'"
echo "2. Navigate to the distinctive white salt flat area"
echo "3. Create a placemark named 'Badwater Basin - North America's Lowest Point'"
echo "4. In the description, document the coordinates and elevation"
echo "5. Export the placemark to: /home/ga/Documents/badwater_basin.kml"
echo ""
echo "============================================================"