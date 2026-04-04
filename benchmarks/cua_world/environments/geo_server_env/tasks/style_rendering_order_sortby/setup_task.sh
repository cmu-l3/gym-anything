#!/bin/bash
echo "=== Setting up style_rendering_order_sortby task ==="

source /workspace/scripts/task_utils.sh

# Record initial style count to detect additions
INITIAL_COUNT=$(get_style_count)
echo "$INITIAL_COUNT" > /tmp/initial_style_count
echo "Initial style count: $INITIAL_COUNT"

# Ensure Firefox is running and logged in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' &
    sleep 5
fi

# Wait for window and ensure login
wait_for_window "firefox\|mozilla" 30
ensure_logged_in

# Focus Firefox
focus_firefox
DISPLAY=:1 xdotool mousemove 960 540 click 1
sleep 1

# Generate integrity nonce
NONCE=$(generate_result_nonce)
echo "Result nonce: $NONCE"

# Snapshot access log for GUI interaction detection
snapshot_access_log

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="