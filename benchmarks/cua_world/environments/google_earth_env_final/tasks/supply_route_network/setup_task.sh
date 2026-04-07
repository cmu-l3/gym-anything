#!/bin/bash
echo "=== Setting up Supply Route Network task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts
rm -f /home/ga/Documents/chicago_distribution_network.kml 2>/dev/null || true
rm -f /home/ga/Documents/*.kml 2>/dev/null || true

# Ensure Documents directory exists with correct permissions
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
chmod 755 /home/ga/Documents

# Record initial state - count existing KML files
INITIAL_KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_KML_COUNT" > /tmp/initial_kml_count.txt
echo "Initial KML file count: $INITIAL_KML_COUNT"

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
WINDOW_FOUND=false
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after $i seconds"
        WINDOW_FOUND=true
        break
    fi
    sleep 1
done

if [ "$WINDOW_FOUND" = "false" ]; then
    echo "WARNING: Google Earth window not detected within timeout"
fi

# Get window ID
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -i "Google Earth" | head -1 | awk '{print $1}')
echo "Window ID: $WINDOW_ID"

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

# Navigate to Chicago area to provide geographic context
echo "Navigating to Chicago metropolitan area..."
DISPLAY=:1 xdotool key ctrl+f  # Open search/fly-to
sleep 2
DISPLAY=:1 xdotool type "Chicago, Illinois, USA"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 5

# Close search panel if still open
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Zoom out a bit to show the broader Chicago metro area
# (Mouse scroll or use + key)
DISPLAY=:1 xdotool key minus 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key minus 2>/dev/null || true
sleep 1

# Take initial screenshot to record starting state
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

# Record Google Earth process info
GE_PID=$(pgrep -f google-earth-pro | head -1)
echo "$GE_PID" > /tmp/google_earth_pid.txt
echo "Google Earth PID: $GE_PID"

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Create a Supply Chain Route Network Map"
echo "============================================================"
echo ""
echo "Create a folder 'Chicago Distribution Network' containing:"
echo ""
echo "PATH 1: 'Primary Route - Hub to Regional DC'"
echo "  From: O'Hare (41.9742°N, 87.9073°W)"
echo "  To:   Joliet (41.4545°N, 88.0817°W)"
echo "  Color: RED, Width: 3px"
echo ""
echo "PATH 2: 'Primary Route - Regional DC to South Hub'"
echo "  From: Joliet (41.4545°N, 88.0817°W)"
echo "  To:   University Park (41.4428°N, 87.7214°W)"
echo "  Color: RED, Width: 3px"
echo ""
echo "PATH 3: 'Secondary Route - East Connection'"
echo "  From: University Park (41.4428°N, 87.7214°W)"
echo "  To:   Gary, IN (41.5934°N, 87.3464°W)"
echo "  Color: BLUE, Width: 2px"
echo ""
echo "Export folder as KML to:"
echo "  /home/ga/Documents/chicago_distribution_network.kml"
echo ""
echo "Tips:"
echo "  - Add > Path (or Ctrl+Shift+T) to create paths"
echo "  - Right-click path > Properties for styling"
echo "  - Right-click folder > Save Place As... to export KML"
echo "============================================================"