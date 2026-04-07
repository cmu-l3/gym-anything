#!/bin/bash
set -e
echo "=== Setting up Ocean Floor Bathymetry Task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure Documents directory exists and is clean
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any previous task artifacts to ensure clean state
rm -f /home/ga/Documents/atlantic_surface.png 2>/dev/null || true
rm -f /home/ga/Documents/atlantic_bathymetry.png 2>/dev/null || true

# Record initial myplaces.kml state if it exists (for placemark detection)
INITIAL_PLACEMARK_COUNT="0"
if [ -f /home/ga/.googleearth/myplaces.kml ]; then
    cp /home/ga/.googleearth/myplaces.kml /tmp/initial_myplaces.kml 2>/dev/null || true
    INITIAL_PLACEMARK_COUNT=$(grep -c "<Placemark>" /home/ga/.googleearth/myplaces.kml 2>/dev/null || echo "0")
fi
echo "$INITIAL_PLACEMARK_COUNT" > /tmp/initial_placemark_count.txt
echo "Initial placemark count: $INITIAL_PLACEMARK_COUNT"

# Save initial state JSON
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_placemark_count": $INITIAL_PLACEMARK_COUNT,
    "surface_screenshot_exists": false,
    "bathymetry_screenshot_exists": false,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth.log 2>&1 &
sleep 5

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected at iteration $i"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Maximize and focus the window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips by pressing Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

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
echo "TASK: Document Ocean Floor Bathymetry"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to 30°N, 42°W (Mid-Atlantic Ridge in the Atlantic Ocean)"
echo "2. Save screenshot of ocean surface view to ~/Documents/atlantic_surface.png"
echo "3. Disable Water Surface layer (View > Water Surface or Layers panel)"
echo "4. Save screenshot of bathymetric terrain to ~/Documents/atlantic_bathymetry.png"
echo "5. Create placemark 'Mid-Atlantic Rift Valley' on the visible rift"
echo ""
echo "Output files:"
echo "  - ~/Documents/atlantic_surface.png"
echo "  - ~/Documents/atlantic_bathymetry.png"
echo "============================================================"