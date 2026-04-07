#!/bin/bash
set -e
echo "=== Setting up Bridge Site Selection task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Record initial myplaces.kml state
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
MYPLACES_ALT="/home/ga/.config/Google/GoogleEarthPro/myplaces.kml"

# Find and backup myplaces
if [ -f "$MYPLACES_PATH" ]; then
    cp "$MYPLACES_PATH" /tmp/myplaces_before_task.kml 2>/dev/null || true
    INITIAL_PLACEMARKS=$(grep -c "<Placemark>" "$MYPLACES_PATH" 2>/dev/null || echo "0")
elif [ -f "$MYPLACES_ALT" ]; then
    cp "$MYPLACES_ALT" /tmp/myplaces_before_task.kml 2>/dev/null || true
    INITIAL_PLACEMARKS=$(grep -c "<Placemark>" "$MYPLACES_ALT" 2>/dev/null || echo "0")
else
    INITIAL_PLACEMARKS="0"
fi
echo "$INITIAL_PLACEMARKS" > /tmp/initial_placemark_count.txt
echo "Initial placemark count: $INITIAL_PLACEMARKS"

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
    if DISPLAY=:1 wmctrl -l | grep -qi "google earth"; then
        echo "Google Earth window detected at attempt $i"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Maximize and focus window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 2

# Navigate to the Dardanelles region to establish initial view
echo "Navigating to Dardanelles strait region..."

# Open search dialog (Ctrl+F or Ctrl+Alt+G)
DISPLAY=:1 xdotool key ctrl+f
sleep 2

# Type the search location
DISPLAY=:1 xdotool type "Dardanelles strait, Turkey"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 8

# Dismiss any popup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Zoom out slightly to show more of the strait
# Use scroll wheel or keyboard shortcuts
DISPLAY=:1 xdotool key minus minus minus 2>/dev/null || true
sleep 2

# Take initial screenshot showing the starting state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

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
    "initial_placemark_count": $INITIAL_PLACEMARKS,
    "initial_screenshot": "/tmp/task_initial_state.png",
    "study_area": {
        "north": 40.25,
        "south": 40.08,
        "description": "Dardanelles strait segment"
    }
}
EOF

echo "=== Bridge Site Selection task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Identify the optimal bridge crossing location"
echo "============================================================"
echo ""
echo "Study Area: Dardanelles strait between 40.08°N and 40.25°N"
echo ""
echo "Your objectives:"
echo "  1. Explore the strait to find candidate narrow sections"
echo "  2. Use the Ruler tool (Tools > Ruler) to measure widths"
echo "  3. Identify the narrowest crossing point"
echo "  4. Create a placemark named 'Bridge_Site_Recommendation'"
echo "  5. Include the width measurement in the description"
echo ""
echo "============================================================"