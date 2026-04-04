#!/bin/bash
set -e
echo "=== Setting up Barcelona Block Measurement task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts
echo "Cleaning up previous artifacts..."
rm -f /home/ga/Documents/barcelona_block.kml 2>/dev/null || true
rm -f /home/ga/Documents/barcelona_block.kmz 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Ensure Documents directory exists with proper permissions
sudo -u ga mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record initial state
OUTPUT_PATH="/home/ga/Documents/barcelona_block.kml"
if [ -f "$OUTPUT_PATH" ]; then
    INITIAL_EXISTS="true"
    INITIAL_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
else
    INITIAL_EXISTS="false"
    INITIAL_SIZE="0"
    INITIAL_MTIME="0"
fi

cat > /tmp/initial_state.json << EOF
{
    "output_exists": $INITIAL_EXISTS,
    "output_size": $INITIAL_SIZE,
    "output_mtime": $INITIAL_MTIME,
    "task_start_time": $(date +%s),
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

# Wait for window to appear
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
echo "Maximizing and focusing Google Earth window..."
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs/tips by pressing Escape
echo "Dismissing any startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
echo "Capturing initial state screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Barcelona Eixample Block Measurement"
echo "============================================================"
echo ""
echo "Navigate to Barcelona's Eixample district and create a polygon"
echo "tracing the city block bounded by:"
echo "  - North: Carrer de Mallorca"
echo "  - South: Carrer de València"
echo "  - East: Carrer de Villarroel"
echo "  - West: Carrer del Comte d'Urgell"
echo ""
echo "Instructions:"
echo "  1. Search for 'Barcelona Eixample' or fly to coordinates"
echo "     (approximately 41.389, 2.157)"
echo "  2. Zoom in to see the distinctive octagonal-cornered grid"
echo "  3. Locate the specific block at the intersection of the"
echo "     four streets listed above"
echo "  4. Create a polygon: Add > Polygon (or Ctrl+Shift+G)"
echo "  5. Trace the block perimeter including chamfered corners"
echo "  6. Save the polygon: right-click > Save Place As"
echo "     Save to: ~/Documents/barcelona_block.kml"
echo ""
echo "Expected block dimensions: ~113m sides, ~12,500 sq m area"
echo "============================================================"