#!/bin/bash
set -e
echo "=== Setting up Meteor Crater Annotation task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure X server access
xhost +local: 2>/dev/null || true

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any previous output file (clean slate)
rm -f /home/ga/Documents/meteor_crater.kml 2>/dev/null || true
rm -f /home/ga/Documents/meteor_crater.kmz 2>/dev/null || true

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "output_file_existed": false,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Store reference data for verification (hidden from agent)
mkdir -p /var/lib/task_verification
chmod 700 /var/lib/task_verification
cat > /var/lib/task_verification/reference.json << 'EOF'
{
    "crater_center_lat": 35.028,
    "crater_center_lon": -111.022,
    "crater_diameter_km": 1.2,
    "crater_area_km2": 1.13,
    "acceptable_centroid_radius_km": 5.0,
    "acceptable_area_tolerance": 0.30
}
EOF

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Launch Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "google earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 2
done

# Check if window appeared
if ! DISPLAY=:1 wmctrl -l | grep -qi "google earth"; then
    echo "WARNING: Google Earth window not detected, attempting restart..."
    pkill -f google-earth-pro 2>/dev/null || true
    sleep 2
    nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
    sleep 10
fi

# Maximize and focus the window
sleep 2
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips by pressing Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Record window state
WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
echo "Current windows:"
echo "$WINDOW_LIST"

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Create Geological Annotation of Meteor Crater"
echo "============================================================"
echo ""
echo "Requirements:"
echo "1. Navigate to Meteor Crater, Arizona (~35.028°N, 111.022°W)"
echo "2. Use Add > Polygon to trace the crater rim"
echo "3. Name: 'Barringer Crater Rim'"
echo "4. Add description about impact crater (~50,000 years old, ~1.2km diameter)"
echo "5. Export to: /home/ga/Documents/meteor_crater.kml"
echo ""
echo "============================================================"