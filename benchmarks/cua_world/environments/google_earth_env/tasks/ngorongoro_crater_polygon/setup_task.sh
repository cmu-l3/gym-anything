#!/bin/bash
set -euo pipefail

echo "=== Setting up Ngorongoro Crater Polygon task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Create output directory
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents 2>/dev/null || true

# Remove any pre-existing output file (ensure clean state)
rm -f /home/ga/Documents/ngorongoro_habitat.kml 2>/dev/null || true

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "output_exists": false,
    "output_size": 0,
    "timestamp": "$(date -Iseconds)"
}
EOF
echo "Initial state recorded"

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
    if wmctrl -l 2>/dev/null | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Get window ID
GE_WINDOW=$(wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | awk '{print $1}')
if [ -n "$GE_WINDOW" ]; then
    echo "Google Earth window ID: $GE_WINDOW"
    
    # Maximize the window
    wmctrl -i -r "$GE_WINDOW" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Focus the window
    wmctrl -i -a "$GE_WINDOW" 2>/dev/null || true
    sleep 1
else
    echo "WARNING: Could not find Google Earth window"
fi

# Dismiss any startup dialogs/tips
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
echo "Capturing initial state screenshot..."
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
echo "TASK: Create a Conservation Habitat Polygon"
echo "============================================================"
echo ""
echo "You need to:"
echo ""
echo "1. Navigate to Ngorongoro Crater, Tanzania"
echo "   - Use Search (Ctrl+F or click search icon)"
echo "   - Search for 'Ngorongoro Crater, Tanzania'"
echo "   - Zoom to eye altitude 15-25 km to see full crater"
echo ""
echo "2. Create a polygon around the crater floor"
echo "   - Go to Add > Polygon (or use toolbar)"
echo "   - Click around the crater floor perimeter (inner rim)"
echo "   - Use at least 15 vertices for accuracy"
echo ""
echo "3. Style the polygon:"
echo "   - Name: 'Ngorongoro Crater Floor'"
echo "   - Fill color: Green"
echo "   - Fill opacity: 30-40%"
echo "   - Line color: Red"
echo "   - Line width: 2.0+"
echo ""
echo "4. Save the polygon as KML:"
echo "   - Right-click polygon in Places panel"
echo "   - Select 'Save Place As...'"
echo "   - Save to: ~/Documents/ngorongoro_habitat.kml"
echo ""
echo "============================================================"