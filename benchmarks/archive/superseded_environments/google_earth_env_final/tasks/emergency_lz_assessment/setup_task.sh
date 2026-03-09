#!/bin/bash
set -e
echo "=== Setting up Emergency LZ Assessment task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts
rm -f /home/ga/Documents/emergency_lz_assessment.kml 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/initial_state.json 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record initial state - count any existing KML files
INITIAL_KML_COUNT=$(find /home/ga/Documents -name "*.kml" 2>/dev/null | wc -l || echo "0")
INITIAL_KMZ_COUNT=$(find /home/ga/Documents -name "*.kmz" 2>/dev/null | wc -l || echo "0")

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_kml_count": $INITIAL_KML_COUNT,
    "initial_kmz_count": $INITIAL_KMZ_COUNT,
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

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "Warning: Google Earth window not detected after 60 seconds"
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Maximize and focus the window
echo "Maximizing and focusing Google Earth window..."
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Try to dismiss any startup dialogs/tips by pressing Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
echo "Capturing initial state screenshot..."
scrot /tmp/task_initial_state.png 2>/dev/null || \
    import -window root /tmp/task_initial_state.png 2>/dev/null || true

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
echo "EMERGENCY HELICOPTER LANDING ZONE ASSESSMENT"
echo "============================================================"
echo ""
echo "SCENARIO: A climbing accident has been reported near"
echo "Rifugio Lagazuoi in the Dolomites mountains, Italy."
echo ""
echo "ACCIDENT COORDINATES: 46.5289°N, 12.0078°E"
echo ""
echo "YOUR TASK:"
echo "1. Navigate to the accident location"
echo "2. Identify at least 3 helicopter landing zones within 5km"
echo "3. Create placemarks with: name, coordinates, elevation,"
echo "   dimensions (measured), and terrain notes"
echo "4. Organize placemarks in folder 'Emergency LZ Assessment'"
echo "5. Save to: ~/Documents/emergency_lz_assessment.kml"
echo ""
echo "============================================================"