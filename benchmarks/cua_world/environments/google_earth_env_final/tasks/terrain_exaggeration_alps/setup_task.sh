#!/bin/bash
set -euo pipefail

echo "=== Setting up terrain_exaggeration_alps task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Remove any previous output file
OUTPUT_PATH="/home/ga/matterhorn_exaggerated.png"
if [ -f "$OUTPUT_PATH" ]; then
    echo "Removing previous output file..."
    rm -f "$OUTPUT_PATH"
fi

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "output_existed_before": false,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Create Google Earth config directories
CONFIG_DIR="/home/ga/.config/Google"
EARTH_DIR="/home/ga/.googleearth"

mkdir -p "$CONFIG_DIR"
mkdir -p "$EARTH_DIR"

# Reset elevation exaggeration to default (1.0) in config files
# Google Earth Pro stores settings in various locations depending on version
echo "Resetting terrain exaggeration to default (1.0)..."

# Try to modify existing config files to reset exaggeration
for config_file in "$CONFIG_DIR/GoogleEarthPro.conf" "$EARTH_DIR/GoogleEarthPro.conf" "$EARTH_DIR/myplaces.kml"; do
    if [ -f "$config_file" ]; then
        # Reset any exaggeration settings to 1.0
        sed -i 's/elevationExaggeration=[0-9.]*/elevationExaggeration=1.0/g' "$config_file" 2>/dev/null || true
        sed -i 's/terrainExaggeration=[0-9.]*/terrainExaggeration=1.0/g' "$config_file" 2>/dev/null || true
        sed -i 's/<exaggeration>[0-9.]*<\/exaggeration>/<exaggeration>1.0<\/exaggeration>/g' "$config_file" 2>/dev/null || true
        echo "Reset exaggeration in: $config_file"
    fi
done

# Ensure proper ownership
chown -R ga:ga "$CONFIG_DIR" 2>/dev/null || true
chown -R ga:ga "$EARTH_DIR" 2>/dev/null || true
chown -R ga:ga /home/ga/ 2>/dev/null || true

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
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Verify Google Earth is running
if ! wmctrl -l | grep -qi "Google Earth"; then
    echo "WARNING: Google Earth window not detected!"
else
    echo "Google Earth window found: $(wmctrl -l | grep -i 'Google Earth')"
fi

# Maximize and focus the Google Earth window
sleep 2
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
wmctrl -a "Google Earth" 2>/dev/null || true

# Dismiss any startup dialogs/tips (press Escape a few times)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state screenshot..."
scrot /tmp/task_initial_state.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

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
echo "TASK: Configure Terrain Exaggeration for Alps Visualization"
echo "============================================================"
echo ""
echo "Goal: Create a dramatic 3D visualization of the Matterhorn"
echo ""
echo "Steps:"
echo "  1. Open Settings: Tools > Options"
echo "  2. Go to '3D View' tab"
echo "  3. Set 'Elevation Exaggeration' to 2.5"
echo "  4. Click OK/Apply to save settings"
echo "  5. Navigate to Matterhorn (search: 'Matterhorn, Switzerland')"
echo "     Or use coordinates: 45.9766, 7.6586"
echo "  6. Tilt the view to show 3D perspective"
echo "     (Shift+scroll or use navigation controls)"
echo "  7. Save screenshot to: /home/ga/matterhorn_exaggerated.png"
echo "     (File > Save > Save Image...)"
echo ""
echo "Target location: Matterhorn, Switzerland (45.9766°N, 7.6586°E)"
echo "Target exaggeration: 2.5x"
echo "Output file: /home/ga/matterhorn_exaggerated.png"
echo "============================================================"