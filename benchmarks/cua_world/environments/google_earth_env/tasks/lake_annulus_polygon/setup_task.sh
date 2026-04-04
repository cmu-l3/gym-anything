#!/bin/bash
echo "=== Setting up Taal Lake Annulus Polygon task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Create output directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any existing output files to ensure clean state
rm -f /home/ga/Documents/taal_lake_polygon.kml 2>/dev/null || true
rm -f /home/ga/Documents/taal_lake_polygon.kmz 2>/dev/null || true

# Record initial state
INITIAL_KML_EXISTS="false"
if [ -f "/home/ga/Documents/taal_lake_polygon.kml" ]; then
    INITIAL_KML_EXISTS="true"
fi

cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "kml_exists": $INITIAL_KML_EXISTS,
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
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "Warning: Google Earth window not detected within timeout"
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

# Try to dismiss any startup dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot as evidence of starting state
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
echo "TASK: Create Annulus Polygon for Taal Lake Water Area"
echo "============================================================"
echo ""
echo "Location: Taal Lake, Batangas, Philippines"
echo "         (A lake with a volcanic island in its center)"
echo ""
echo "You need to:"
echo "1. Navigate to Taal Lake, Philippines"
echo "2. Create a polygon named 'Taal Lake Water Area'"
echo "3. Draw the outer boundary around the entire lake"
echo "4. Add an INNER boundary (hole) around Volcano Island"
echo "5. Export to: /home/ga/Documents/taal_lake_polygon.kml"
echo ""
echo "CRITICAL: The polygon must have an inner hole to exclude"
echo "          Volcano Island from the water area calculation!"
echo "============================================================"