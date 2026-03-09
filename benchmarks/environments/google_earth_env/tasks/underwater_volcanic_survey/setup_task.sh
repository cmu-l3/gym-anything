#!/bin/bash
set -e
echo "=== Setting up Underwater Volcanic Survey task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Create output directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any previous task artifacts to ensure clean state
rm -f /home/ga/Documents/axial_seamount_survey.png 2>/dev/null || true
rm -f /tmp/task_initial_state.png 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record initial placemark state
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"
MYPLACES_ALT="/home/ga/.config/Google/googleearth/myplaces.kml"

INITIAL_PLACEMARK_COUNT="0"
if [ -f "$MYPLACES_FILE" ]; then
    INITIAL_PLACEMARK_COUNT=$(grep -c "<Placemark>" "$MYPLACES_FILE" 2>/dev/null || echo "0")
    # Remove any existing Axial Seamount placemarks to ensure clean state
    cp "$MYPLACES_FILE" "/tmp/myplaces_backup_$(date +%s).kml" 2>/dev/null || true
    sed -i '/<Placemark>.*<name>Axial Seamount<\/name>/,/<\/Placemark>/d' "$MYPLACES_FILE" 2>/dev/null || true
elif [ -f "$MYPLACES_ALT" ]; then
    INITIAL_PLACEMARK_COUNT=$(grep -c "<Placemark>" "$MYPLACES_ALT" 2>/dev/null || echo "0")
    cp "$MYPLACES_ALT" "/tmp/myplaces_backup_$(date +%s).kml" 2>/dev/null || true
    sed -i '/<Placemark>.*<name>Axial Seamount<\/name>/,/<\/Placemark>/d' "$MYPLACES_ALT" 2>/dev/null || true
fi
echo "$INITIAL_PLACEMARK_COUNT" > /tmp/initial_placemark_count.txt
echo "Initial placemark count: $INITIAL_PLACEMARK_COUNT"

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth Pro window..."
WINDOW_FOUND=false
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth Pro window detected after ${i} seconds"
        WINDOW_FOUND=true
        break
    fi
    sleep 1
done

if [ "$WINDOW_FOUND" = "false" ]; then
    echo "WARNING: Google Earth Pro window not detected within 60 seconds"
fi

# Additional wait for full initialization
sleep 3

# Maximize and focus the window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs/tips by pressing Escape
xdotool key Escape 2>/dev/null || true
sleep 1
xdotool key Escape 2>/dev/null || true
sleep 1

# Reset view to default (press 'r' key)
xdotool key r 2>/dev/null || true
sleep 2

# Take initial state screenshot for evidence
scrot /tmp/task_initial_state.png 2>/dev/null || true
if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
fi

# Save initial state to JSON
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_placemark_count": $INITIAL_PLACEMARK_COUNT,
    "screenshot_exists": $([ -f /tmp/task_initial_state.png ] && echo "true" || echo "false"),
    "google_earth_running": $(pgrep -f google-earth-pro > /dev/null && echo "true" || echo "false")
}
EOF

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Submarine Volcanic Feature Documentation"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Disable water surface visualization:"
echo "   Go to View menu > uncheck 'Water Surface'"
echo "   This reveals the ocean floor bathymetry"
echo ""
echo "2. Navigate to Axial Seamount:"
echo "   Location: approximately 45.95°N, 130.01°W"
echo "   (About 480 km off the Oregon coast)"
echo "   Use search or fly to the coordinates"
echo ""
echo "3. Create a placemark at the seamount summit:"
echo "   Name: 'Axial Seamount'"
echo "   Description: 'Active submarine volcano, Juan de Fuca Ridge'"
echo ""
echo "4. Save a screenshot showing the underwater terrain to:"
echo "   /home/ga/Documents/axial_seamount_survey.png"
echo ""
echo "============================================================"