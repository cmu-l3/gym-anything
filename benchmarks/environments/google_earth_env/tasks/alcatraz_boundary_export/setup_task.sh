#!/bin/bash
set -e
echo "=== Setting up Alcatraz Boundary Export task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts
echo "Cleaning previous artifacts..."
rm -f /home/ga/Documents/alcatraz_boundary.kml 2>/dev/null || true
rm -f /home/ga/Documents/alcatraz_boundary.kmz 2>/dev/null || true
rm -f /home/ga/Documents/Alcatraz*.kml 2>/dev/null || true
rm -f /home/ga/Documents/Alcatraz*.kmz 2>/dev/null || true

# Ensure Documents directory exists with proper permissions
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
chmod 755 /home/ga/Documents

# Record initial state
INITIAL_KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_KML_COUNT" > /tmp/initial_kml_count.txt

# Save initial state as JSON
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_kml_count": $INITIAL_KML_COUNT,
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
WINDOW_FOUND=false
for i in {1..60}; do
    if wmctrl -l 2>/dev/null | grep -qi "google earth"; then
        echo "Google Earth window detected after ${i} seconds"
        WINDOW_FOUND=true
        break
    fi
    sleep 1
done

if [ "$WINDOW_FOUND" = "false" ]; then
    echo "WARNING: Google Earth window not detected within timeout"
fi

# Additional wait for full initialization
sleep 5

# Dismiss any startup dialogs
echo "Dismissing startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# Maximize window
echo "Maximizing Google Earth window..."
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
wmctrl -r "earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
wmctrl -a "Google Earth" 2>/dev/null || wmctrl -a "earth" 2>/dev/null || true
sleep 1

# Navigate to California as starting point (not directly to Alcatraz)
echo "Setting initial view to California..."
DISPLAY=:1 xdotool key ctrl+f 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool type "California, USA"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 5

# Close search panel
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
echo "Capturing initial state screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

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
echo "TASK: Create Alcatraz Island Boundary and Export as KML"
echo "============================================================"
echo ""
echo "Instructions:"
echo "1. Navigate to Alcatraz Island in San Francisco Bay"
echo "   (Search for 'Alcatraz Island' or coordinates 37.827, -122.423)"
echo ""
echo "2. Use the polygon tool: Add > Polygon (or Ctrl+Shift+G)"
echo ""
echo "3. Trace the island's coastline by clicking multiple points"
echo "   around the perimeter (follow the irregular shoreline)"
echo ""
echo "4. Name the polygon 'Alcatraz_Boundary' in the dialog"
echo ""
echo "5. Right-click the polygon in My Places > Save Place As..."
echo ""
echo "6. Save as KML (not KMZ) to:"
echo "   /home/ga/Documents/alcatraz_boundary.kml"
echo ""
echo "============================================================"