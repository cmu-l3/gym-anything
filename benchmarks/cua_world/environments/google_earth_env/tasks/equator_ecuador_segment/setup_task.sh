#!/bin/bash
set -e
echo "=== Setting up equator_ecuador_segment task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts
rm -f /home/ga/Documents/ecuador_equator.kml 2>/dev/null || true
rm -f /home/ga/Documents/*.kml 2>/dev/null || true
rm -f /home/ga/Documents/*.kmz 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record initial state
INITIAL_KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_KML_COUNT" > /tmp/initial_kml_count.txt

# Clear Google Earth's saved places to ensure clean state
if [ -d "/home/ga/.googleearth" ]; then
    # Backup and clear myplaces to start fresh
    cp /home/ga/.googleearth/myplaces.kml /home/ga/.googleearth/myplaces.backup.kml 2>/dev/null || true
    rm -f /home/ga/.googleearth/myplaces.kml 2>/dev/null || true
fi

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_setup.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -iE "(google earth|earth pro)"; then
        echo "Google Earth window detected at attempt $i"
        break
    fi
    sleep 2
done

# Give Google Earth time to fully initialize and load imagery
sleep 10

# Maximize and focus Google Earth window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup tips or dialogs
xdotool key Escape 2>/dev/null || true
sleep 1
xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
scrot /tmp/task_initial_state.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Save initial state JSON
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_kml_count": $INITIAL_KML_COUNT,
    "google_earth_running": $(pgrep -f google-earth-pro > /dev/null && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Create equator documentation for Ecuador"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to Ecuador's Pacific coast (western edge)"
echo "2. Create a path tracing the equator (0° latitude) across Ecuador"
echo "   - Name it 'Equator Through Ecuador'"
echo "   - Follow latitude 0° from coast to eastern border"
echo ""
echo "3. Navigate to the Mitad del Mundo monument (near Quito)"
echo "   - Location: approximately 0°0'0\", 78°27'W"
echo "4. Create a placemark named 'Mitad del Mundo Monument'"
echo "   - Add description with coordinates"
echo ""
echo "5. Create folder 'Ecuador Equator Project' with both items"
echo "6. Export to: /home/ga/Documents/ecuador_equator.kml"
echo ""
echo "Expected equator length through Ecuador: ~320-330 km"
echo "============================================================"