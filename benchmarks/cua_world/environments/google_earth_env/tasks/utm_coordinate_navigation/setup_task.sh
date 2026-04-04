#!/bin/bash
set -e
echo "=== Setting up UTM Coordinate Navigation task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Kill any existing Google Earth instances for clean start
echo "Stopping any existing Google Earth instances..."
pkill -f "google-earth" 2>/dev/null || true
sleep 2

# Create necessary directories
mkdir -p /home/ga/.config/Google
mkdir -p /home/ga/.googleearth
chown -R ga:ga /home/ga/.config/Google
chown -R ga:ga /home/ga/.googleearth

# Save initial config state for comparison
CONFIG_FILE="/home/ga/.config/Google/GoogleEarthPro.conf"
BACKUP_CONFIG="/home/ga/.googleearth/GoogleEarth.conf"

if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" /tmp/initial_config.txt
    INITIAL_CONFIG_EXISTS="true"
    INITIAL_CONFIG_MTIME=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo "0")
    # Ensure coordinate format is set to Decimal Degrees (value 0) for clean start
    sed -i 's/LatLonDisplayFormat=.*/LatLonDisplayFormat=0/' "$CONFIG_FILE" 2>/dev/null || true
    echo "Reset config to Decimal Degrees format"
else
    echo "no_initial_config" > /tmp/initial_config.txt
    INITIAL_CONFIG_EXISTS="false"
    INITIAL_CONFIG_MTIME="0"
fi

if [ -f "$BACKUP_CONFIG" ]; then
    sed -i 's/LatLonDisplayFormat=.*/LatLonDisplayFormat=0/' "$BACKUP_CONFIG" 2>/dev/null || true
fi

# Record initial state as JSON
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_config_exists": $INITIAL_CONFIG_EXISTS,
    "initial_config_mtime": $INITIAL_CONFIG_MTIME,
    "initial_format": "decimal_degrees",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Maximize and focus the window
echo "Maximizing Google Earth window..."
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup tips/dialogs by pressing Escape multiple times
echo "Dismissing any startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Navigate to a neutral global view (zoom out)
echo "Setting neutral starting view..."
DISPLAY=:1 xdotool key ctrl+Home 2>/dev/null || true
sleep 3

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== UTM Coordinate Navigation task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Configure UTM coordinates and navigate to Devils Tower"
echo "============================================================"
echo ""
echo "Steps to complete:"
echo "1. Open Tools → Options (preferences)"
echo "2. Go to '3D View' tab"
echo "3. Change 'Show Lat/Long' to 'Universal Transverse Mercator'"
echo "4. Click Apply, then OK"
echo "5. Search for: 13T 534350mE 4940750mN"
echo "6. Verify Devils Tower is visible"
echo ""
echo "Target: Devils Tower National Monument, Wyoming"
echo "============================================================"