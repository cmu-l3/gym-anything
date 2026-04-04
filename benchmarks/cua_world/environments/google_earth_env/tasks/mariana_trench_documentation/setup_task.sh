#!/bin/bash
set -e
echo "=== Setting up Mariana Trench Documentation Task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts
rm -f /home/ga/Documents/challenger_deep.kml 2>/dev/null || true
rm -f /home/ga/Documents/challenger_deep.kmz 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record initial state - check if any challenger-related placemarks exist
INITIAL_PLACEMARK_EXISTS="false"
if [ -f "/home/ga/.googleearth/myplaces.kml" ]; then
    if grep -qi "challenger" /home/ga/.googleearth/myplaces.kml 2>/dev/null; then
        INITIAL_PLACEMARK_EXISTS="true"
        echo "Warning: Found existing challenger placemark, attempting to clean..."
        # Create backup
        cp /home/ga/.googleearth/myplaces.kml /home/ga/.googleearth/myplaces.kml.backup 2>/dev/null || true
    fi
fi

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_placemark_exists": $INITIAL_PLACEMARK_EXISTS,
    "output_path": "/home/ga/Documents/challenger_deep.kml",
    "timestamp": "$(date -Iseconds)"
}
EOF
echo "Initial state saved:"
cat /tmp/initial_state.json

# Kill any existing Google Earth instances for clean start
echo "Stopping any existing Google Earth instances..."
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Maximize and focus Google Earth
echo "Maximizing and focusing Google Earth..."
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
wmctrl -a "Google Earth" 2>/dev/null || true

# Dismiss any startup dialogs with Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
echo "Capturing initial state screenshot..."
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
echo "TASK: Document the Challenger Deep in the Mariana Trench"
echo "============================================================"
echo ""
echo "Instructions:"
echo "1. Enable ocean floor visualization:"
echo "   - In the left sidebar, find and expand 'Layers'"
echo "   - Look for 'Ocean' layer category and enable it"
echo ""
echo "2. Navigate to Challenger Deep:"
echo "   - Use search bar (Ctrl+F) or click the search icon"
echo "   - Search for: 11.3493, 142.1996"
echo "   - Or search for: Challenger Deep"
echo ""
echo "3. Create a documented placemark:"
echo "   - Add > Placemark (or press Ctrl+Shift+P)"
echo "   - Name: Challenger Deep"
echo "   - Description: Include depth (~-10,994m) and 'Mariana Trench'"
echo ""
echo "4. Export the placemark:"
echo "   - Right-click the placemark in My Places"
echo "   - Select 'Save Place As...'"
echo "   - Save to: /home/ga/Documents/challenger_deep.kml"
echo "============================================================"