#!/bin/bash
set -euo pipefail

echo "=== Setting up Thames River Path task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create Documents directory if it doesn't exist
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any previous task artifacts
rm -f /home/ga/Documents/thames_path.kml 2>/dev/null || true
rm -f /home/ga/Documents/thames_path.kmz 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record initial state
KML_PATH="/home/ga/Documents/thames_path.kml"
if [ -f "$KML_PATH" ]; then
    INITIAL_EXISTS="true"
    INITIAL_SIZE=$(stat -c%s "$KML_PATH" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c%Y "$KML_PATH" 2>/dev/null || echo "0")
else
    INITIAL_EXISTS="false"
    INITIAL_SIZE="0"
    INITIAL_MTIME="0"
fi

cat > /tmp/initial_state.json << EOF
{
    "kml_exists": $INITIAL_EXISTS,
    "kml_size": $INITIAL_SIZE,
    "kml_mtime": $INITIAL_MTIME,
    "task_start_time": $(cat /tmp/task_start_time.txt),
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
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_thames.log 2>&1 &
sleep 8

# Wait for window to appear
echo "Waiting for Google Earth Pro window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth Pro window detected"
        break
    fi
    sleep 1
done

# Get window ID
WINDOW_ID=$(wmctrl -l | grep -i "Google Earth" | head -1 | awk '{print $1}')
echo "Window ID: $WINDOW_ID"

# Maximize and focus the Google Earth window
sleep 2
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
wmctrl -a "Google Earth" 2>/dev/null || true

# Dismiss any startup dialogs/tips by pressing Escape
sleep 3
xdotool key Escape 2>/dev/null || true
sleep 1
xdotool key Escape 2>/dev/null || true

# Take initial screenshot to record starting state
sleep 2
scrot /tmp/task_initial_state.png 2>/dev/null || true

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
echo "TASK: Trace the River Thames and Save as KML"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to London, UK (search for 'Tower Bridge, London')"
echo ""
echo "2. Create a path using Add > Path (or Ctrl+Shift+T)"
echo "   - Start at Tower Bridge (east)"
echo "   - Click multiple points along the Thames (at least 8 points)"
echo "   - End at Westminster Bridge (west, near Big Ben)"
echo ""
echo "3. Name the path and click OK to save it"
echo ""
echo "4. Export as KML: File > Save > Save Place As..."
echo "   - Navigate to ~/Documents/"
echo "   - Filename: thames_path.kml"
echo "   - Save as type: KML"
echo ""
echo "Expected output: ~/Documents/thames_path.kml"
echo "============================================================"