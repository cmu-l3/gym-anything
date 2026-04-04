#!/bin/bash
set -e
echo "=== Setting up Flight Simulator Grand Canyon task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts
rm -f /home/ga/grand_canyon_flight.png 2>/dev/null || true
rm -f /home/ga/*.png 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(date +%s),
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
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i}s"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "WARNING: Google Earth window not detected after 60s"
    fi
    sleep 1
done

# Additional wait for full initialization (Google Earth loads terrain data)
echo "Waiting for Google Earth to fully initialize..."
sleep 10

# Maximize the window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips by pressing Escape
echo "Dismissing any startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Navigate to Grand Canyon area to make the task easier
# The agent can then use "Start at current view" in flight simulator
echo "Pre-navigating to Grand Canyon area..."

# Open search with Ctrl+F
DISPLAY=:1 xdotool key ctrl+f
sleep 2

# Type the search query
DISPLAY=:1 xdotool type "Grand Canyon Village, Arizona"
sleep 1

# Press Enter to search
DISPLAY=:1 xdotool key Return
sleep 8  # Wait for fly-to animation and imagery loading

# Press Escape to close search panel
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Tilt the view slightly to show 3D terrain (press 't' to tilt or use arrow keys)
DISPLAY=:1 xdotool key t 2>/dev/null || true
sleep 1

# Focus the main window again
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true

# Take initial screenshot to record starting state
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Flight Simulator Grand Canyon task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Enter Flight Simulator and capture cockpit view"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Access the Flight Simulator:"
echo "   - Press Ctrl+Alt+A, OR"
echo "   - Go to Tools > Enter Flight Simulator"
echo ""
echo "2. In the Flight Simulator dialog:"
echo "   - Select an aircraft (F-16 or SR22)"
echo "   - Click 'Start at current view' (you're near Grand Canyon)"
echo "   - Click 'Start Flight'"
echo ""
echo "3. Once flying:"
echo "   - Use arrow keys to control the aircraft"
echo "   - Orient view to show Grand Canyon terrain below"
echo "   - The cockpit instruments should be visible"
echo ""
echo "4. Save a screenshot to: /home/ga/grand_canyon_flight.png"
echo "   - Press Print Screen and save, OR"
echo "   - Use: scrot /home/ga/grand_canyon_flight.png"
echo ""
echo "Current location: Grand Canyon, Arizona"
echo "============================================================"