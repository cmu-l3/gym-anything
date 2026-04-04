#!/bin/bash
set -e
echo "=== Setting up location_disambiguation task ==="

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
rm -f /home/ga/Documents/cambridge_research.kml 2>/dev/null || true
rm -f /home/ga/Documents/cambridge*.kml 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Ensure Documents directory exists with proper permissions
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
chmod 755 /home/ga/Documents

# Record initial state - check for any existing KML files
INITIAL_KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_KML_COUNT" > /tmp/initial_kml_count.txt
echo "Initial KML file count: $INITIAL_KML_COUNT"

# Clear Google Earth saved places for clean state (backup first)
if [ -f /home/ga/.googleearth/myplaces.kml ]; then
    cp /home/ga/.googleearth/myplaces.kml /home/ga/.googleearth/myplaces.backup.$(date +%s).kml 2>/dev/null || true
fi

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
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
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

# Maximize and focus the window
echo "Maximizing and focusing Google Earth window..."
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Try to dismiss any startup dialogs or tips
echo "Dismissing startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Reset view to global perspective
echo "Resetting to global view..."
DISPLAY=:1 xdotool key ctrl+Home 2>/dev/null || true
sleep 2

# Record window state
WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
echo "Current windows:"
echo "$WINDOW_LIST"

# Take screenshot of initial state
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

# Save initial state summary
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_kml_count": $INITIAL_KML_COUNT,
    "google_earth_started": $WINDOW_FOUND,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Location Disambiguation and Documentation"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Search for 'Cambridge' using the search bar (Ctrl+F or click search)"
echo "2. From multiple results, select Cambridge, Massachusetts, USA"
echo "   (NOT Cambridge UK, Cambridge Ontario, etc.)"
echo "3. Navigate to Harvard Yard area (approx. 42.374°N, 71.117°W)"
echo "4. Create a placemark: Add > Placemark (or Ctrl+Shift+P)"
echo "   - Name: 'Cambridge MA Research Point'"
echo "   - Description: Include 'Coordinates: [lat], [lon]'"
echo "5. Save to My Places"
echo "6. Export as KML: File > Save > Save Place As..."
echo "   - Save to: ~/Documents/cambridge_research.kml"
echo ""
echo "============================================================"