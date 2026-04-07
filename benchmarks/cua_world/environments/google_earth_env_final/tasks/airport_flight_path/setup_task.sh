#!/bin/bash
set -e
echo "=== Setting up airport_flight_path task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up any previous task artifacts
rm -f /home/ga/Documents/flight_path.kml 2>/dev/null || true
rm -f /home/ga/Documents/flight_path.kmz 2>/dev/null || true

# Record initial state - check if output file exists
OUTPUT_PATH="/home/ga/Documents/flight_path.kml"
if [ -f "$OUTPUT_PATH" ]; then
    INITIAL_EXISTS="true"
    INITIAL_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
else
    INITIAL_EXISTS="false"
    INITIAL_SIZE="0"
    INITIAL_MTIME="0"
fi

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "output_exists": $INITIAL_EXISTS,
    "output_size": $INITIAL_SIZE,
    "output_mtime": $INITIAL_MTIME,
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "timestamp": "$(date -Iseconds)"
}
EOF
echo "Initial state recorded:"
cat /tmp/initial_state.json

# Clear Google Earth's My Places to start fresh (but backup first)
if [ -d "/home/ga/.googleearth" ]; then
    # Backup existing myplaces if any
    if [ -f "/home/ga/.googleearth/myplaces.kml" ]; then
        cp /home/ga/.googleearth/myplaces.kml /home/ga/.googleearth/myplaces.backup.kml 2>/dev/null || true
    fi
fi

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Launch Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth to load..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected at iteration $i"
        break
    fi
    sleep 2
done

# Additional wait for full initialization (imagery loading, etc.)
sleep 10

# Maximize window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs/tips by pressing Escape
xdotool key Escape 2>/dev/null || true
sleep 1
xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
mkdir -p /tmp/task_evidence
scrot /tmp/task_evidence/initial_state.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_evidence/initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_evidence/initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Create a flight planning path from KSFO to KLAX"
echo "============================================================"
echo ""
echo "Instructions:"
echo "1. Navigate to San Francisco International Airport (KSFO)"
echo "   - Search for 'KSFO' or 'San Francisco International Airport'"
echo ""
echo "2. Add a new path:"
echo "   - Go to Add menu > Path (or use toolbar)"
echo "   - Name it: 'KSFO-KLAX Direct Route'"
echo "   - Click on SFO to place first point"
echo ""
echo "3. Navigate to Los Angeles International Airport (KLAX)"
echo "   - Search for 'KLAX' or 'Los Angeles International Airport'"
echo "   - Click on LAX to place second point"
echo "   - Click OK to save the path"
echo ""
echo "4. Export the path:"
echo "   - Right-click on the path in 'My Places'"
echo "   - Select 'Save Place As...'"
echo "   - Save to: /home/ga/Documents/flight_path.kml"
echo ""
echo "============================================================"