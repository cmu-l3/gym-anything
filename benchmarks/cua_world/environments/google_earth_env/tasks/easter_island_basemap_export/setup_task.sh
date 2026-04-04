#!/bin/bash
echo "=== Setting up Easter Island Basemap Export task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts
rm -f /home/ga/exports/easter_island_basemap.png 2>/dev/null || true

# Record initial state - check if output directory and file exist
OUTPUT_DIR="/home/ga/exports"
OUTPUT_PATH="/home/ga/exports/easter_island_basemap.png"

# Create exports directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Record initial file count in exports directory
INITIAL_FILE_COUNT=$(ls -1 "$OUTPUT_DIR" 2>/dev/null | wc -l || echo "0")

# Save initial state for verification
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "output_dir_exists": true,
    "output_file_existed": false,
    "initial_file_count": $INITIAL_FILE_COUNT,
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
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth Pro window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Maximize and fullscreen the window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the Google Earth window
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips (press Escape a few times)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

# Verify screenshot was captured
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
echo "TASK: Export Easter Island Cartographic Basemap"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to Easter Island (Rapa Nui), Chile"
echo "   Coordinates: -27.1127, -109.3497"
echo "   (Use Search/Fly To feature)"
echo ""
echo "2. Frame the complete island (all 3 volcanic peaks visible)"
echo "   - Terevaka (north)"
echo "   - Poike (east)"  
echo "   - Rano Kau (southwest)"
echo ""
echo "3. Disable overlay layers:"
echo "   - Turn OFF: Labels, Borders, Roads, 3D Buildings"
echo "   - Use View menu or Layers panel in sidebar"
echo ""
echo "4. Ensure top-down (nadir) view, not tilted"
echo "   - Press 'u' to reset tilt if needed"
echo ""
echo "5. Export the image:"
echo "   - File > Save > Save Image"
echo "   - Resolution: at least 1920x1080"
echo "   - Save to: /home/ga/exports/easter_island_basemap.png"
echo ""
echo "============================================================"