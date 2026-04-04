#!/bin/bash
set -e
echo "=== Setting up Grid Navigation to Bermuda Triangle task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure Pictures directory exists
sudo -u ga mkdir -p /home/ga/Pictures
chown ga:ga /home/ga/Pictures

# Remove any previous screenshot from prior attempts
if [ -f "/home/ga/Pictures/bermuda_grid.png" ]; then
    PREV_MTIME=$(stat -c %Y /home/ga/Pictures/bermuda_grid.png 2>/dev/null || echo "0")
    echo "Previous screenshot exists with mtime: $PREV_MTIME"
    rm -f /home/ga/Pictures/bermuda_grid.png
fi

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(date +%s),
    "screenshot_existed": false,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Ensure Google Earth is not running (clean start)
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Clear Google Earth cache to ensure fresh state
rm -rf /home/ga/.googleearth/Cache/* 2>/dev/null || true

# Try to ensure grid is disabled at start (agent must enable it)
EARTH_CONF="/home/ga/.config/Google/GoogleEarthPro.conf"
if [ -f "$EARTH_CONF" ]; then
    # Backup and modify config
    cp "$EARTH_CONF" "$EARTH_CONF.bak" 2>/dev/null || true
    sed -i 's/GridVisible=true/GridVisible=false/g' "$EARTH_CONF" 2>/dev/null || true
    sed -i 's/showLatLonGrid=true/showLatLonGrid=false/g' "$EARTH_CONF" 2>/dev/null || true
    echo "Grid setting reset in config"
fi

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth Pro window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Give extra time for initial globe rendering
sleep 3

# Maximize the window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips by pressing Escape
xdotool key Escape 2>/dev/null || true
sleep 0.5
xdotool key Escape 2>/dev/null || true
sleep 0.5

# Click on the main view to ensure focus (center of screen)
xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 1

# Take screenshot of initial state for evidence
scrot /tmp/task_initial_state.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Record that grid should be disabled initially
echo "false" > /tmp/initial_grid_state.txt

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Enable Grid Overlay and Navigate to Bermuda Triangle"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Enable the latitude/longitude grid overlay"
echo "   (View menu → Grid, or press Ctrl+L)"
echo ""
echo "2. Navigate to coordinates 25°N, 71°W"
echo "   (Search for '25, -71' or '25°N 71°W')"
echo "   This is the approximate center of the Bermuda Triangle"
echo ""
echo "3. Save a screenshot to ~/Pictures/bermuda_grid.png"
echo "   (File → Save → Save Image, or Ctrl+Alt+S)"
echo ""
echo "The screenshot should show:"
echo "  - Grid lines visible over the view"
echo "  - Atlantic Ocean / Bermuda Triangle region"
echo "============================================================"