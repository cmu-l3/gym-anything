#!/bin/bash
set -e
echo "=== Setting up River Sinuosity Analysis task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Remove any previous task artifacts
echo "Cleaning previous artifacts..."
rm -f /home/ga/Documents/mississippi_sinuosity.kml 2>/dev/null || true
rm -f /home/ga/Documents/*sinuosity*.kml 2>/dev/null || true
rm -f /home/ga/Documents/*mississippi*.kml 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record initial state - check if KML already exists
if [ -f "/home/ga/Documents/mississippi_sinuosity.kml" ]; then
    INITIAL_KML_EXISTS="true"
    INITIAL_KML_SIZE=$(stat -c %s "/home/ga/Documents/mississippi_sinuosity.kml" 2>/dev/null || echo "0")
else
    INITIAL_KML_EXISTS="false"
    INITIAL_KML_SIZE="0"
fi

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "kml_exists": $INITIAL_KML_EXISTS,
    "kml_size": $INITIAL_KML_SIZE,
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "timestamp": "$(date -Iseconds)"
}
EOF
echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Google Earth instances for clean start
echo "Stopping any existing Google Earth instances..."
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected (attempt $i)"
        break
    fi
    echo "Waiting... ($i/45)"
    sleep 2
done

# Give it a moment to fully initialize
sleep 3

# Maximize and focus the window
echo "Maximizing and focusing Google Earth window..."
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Try to dismiss any startup dialogs/tips
echo "Dismissing startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# Verify Google Earth is running
if pgrep -f "google-earth" > /dev/null; then
    echo "Google Earth is running"
    GE_RUNNING="true"
else
    echo "WARNING: Google Earth may not have started properly"
    GE_RUNNING="false"
fi

# Take initial screenshot
echo "Capturing initial state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "============================================================"
echo "TASK: River Sinuosity Analysis"
echo "============================================================"
echo ""
echo "Objective: Calculate the sinuosity index of the Mississippi River"
echo "           near Greenville, MS"
echo ""
echo "Start Point: 33.4000°N, 91.0500°W"
echo "End Point:   33.2500°N, 91.2000°W"
echo ""
echo "Steps:"
echo "1. Navigate to the start coordinates on the Mississippi River"
echo "2. Create placemark 'Sinuosity_Start' at start location"
echo "3. Navigate to the end coordinates"  
echo "4. Create placemark 'Sinuosity_End' at end location"
echo "5. Measure straight-line distance (Ruler > Line mode)"
echo "6. Measure channel length along river (Ruler > Path mode)"
echo "7. Create placemark 'Sinuosity_Analysis' with measurements:"
echo "   - Straight-line distance (km)"
echo "   - Channel length (km)"
echo "   - Sinuosity = channel / straight"
echo "   - Classification: Straight/Sinuous/Meandering"
echo "8. Save placemarks in folder 'Mississippi_Sinuosity'"
echo "9. Export folder to ~/Documents/mississippi_sinuosity.kml"
echo ""
echo "Expected sinuosity: ~1.5-1.7 (Meandering)"
echo "============================================================"
echo ""
echo "=== Task setup complete ==="