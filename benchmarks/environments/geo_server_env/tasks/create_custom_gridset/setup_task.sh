#!/bin/bash
echo "=== Setting up create_custom_gridset task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure GeoServer is ready
wait_for_geoserver 60

# Record initial gridsets (to ensure we detect if the user creates a new one)
# GWC REST API usually returns XML by default, try JSON
INITIAL_GRIDSETS=$(curl -s -u "$GS_AUTH" -H "Accept: application/json" "${GS_URL}/gwc/rest/gridsets" 2>/dev/null)
echo "$INITIAL_GRIDSETS" > /tmp/initial_gridsets.json
echo "Initial gridsets recorded"

# Check if the target gridset already exists (it shouldn't, but clean up if it does from a previous run)
if curl -s -u "$GS_AUTH" -o /dev/null -w "%{http_code}" "${GS_URL}/gwc/rest/gridsets/EPSG3035_Europe" | grep -q "200"; then
    echo "WARNING: Target gridset already exists. Attempting to delete..."
    curl -s -u "$GS_AUTH" -X DELETE "${GS_URL}/gwc/rest/gridsets/EPSG3035_Europe"
fi

# Ensure Firefox is running and logged in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' &
    sleep 5
fi
wait_for_window "firefox\|mozilla" 30
ensure_logged_in

# Focus Firefox
focus_firefox
DISPLAY=:1 xdotool mousemove 960 540 click 1
sleep 1

# Snapshot access log for GUI interaction detection
snapshot_access_log

# Generate integrity nonce
NONCE=$(generate_result_nonce)
echo "Result nonce: $NONCE"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== create_custom_gridset task setup complete ==="