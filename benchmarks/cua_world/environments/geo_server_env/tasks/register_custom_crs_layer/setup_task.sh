#!/bin/bash
echo "=== Setting up register_custom_crs_layer task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial state of layers to detect new ones
INITIAL_LAYER_COUNT=$(get_layer_count)
echo "$INITIAL_LAYER_COUNT" > /tmp/initial_layer_count
echo "Initial layer count: $INITIAL_LAYER_COUNT"

# Ensure the source layer exists (ne:ne_countries)
if ! gs_rest_get "layers/ne_countries.json" > /dev/null; then
    echo "WARNING: Source layer ne:ne_countries not found. Task may be difficult."
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

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== register_custom_crs_layer task setup complete ==="