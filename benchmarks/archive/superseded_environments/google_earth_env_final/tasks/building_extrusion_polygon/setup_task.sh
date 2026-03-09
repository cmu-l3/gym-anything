#!/bin/bash
set -e
echo "=== Setting up 3D Building Extrusion task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists and is clean
OUTPUT_DIR="/home/ga/Documents"
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Remove any previous task outputs to ensure clean state
rm -f "$OUTPUT_DIR/proposed_building.kml" 2>/dev/null || true
rm -f "$OUTPUT_DIR/building_visualization.png" 2>/dev/null || true

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "kml_exists_before": false,
    "screenshot_exists_before": false,
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
    sleep 2
done

# Check if window appeared
if ! DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
    echo "WARNING: Google Earth window not detected"
fi

# Maximize and focus the window
sleep 2
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Try to dismiss any startup dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Ensure 3D Buildings layer is mentioned (agent may need to enable it)
echo ""
echo "============================================================"
echo "TASK: Create 3D Building Extrusion in Google Earth Pro"
echo "============================================================"
echo ""
echo "Location: Chicago, IL (41.8839°N, 87.6416°W)"
echo "         Near Ogilvie Transportation Center"
echo ""
echo "Requirements:"
echo "1. Navigate to coordinates: 41.8839, -87.6416"
echo "2. Enable 3D Buildings layer if needed (Layers panel)"
echo "3. Create a polygon (Add > Polygon or Ctrl+Shift+G)"
echo "4. Draw a rectangular shape (~60m x 40m) on the lot"
echo "5. Set polygon properties:"
echo "   - Name: 'Proposed Office Tower'"
echo "   - Altitude: 75 meters"
echo "   - Altitude mode: Relative to Ground"
echo "   - Enable: Extend sides to ground"
echo "   - Fill color: Semi-transparent blue"
echo "6. Save KML to: /home/ga/Documents/proposed_building.kml"
echo "7. Adjust view to show 3D (angled, not top-down)"
echo "8. Save screenshot: /home/ga/Documents/building_visualization.png"
echo "============================================================"

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task setup complete ==="