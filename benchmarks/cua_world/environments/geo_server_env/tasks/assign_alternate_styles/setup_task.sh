#!/bin/bash
echo "=== Setting up assign_alternate_styles task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists
mkdir -p /home/ga/output
chown ga:ga /home/ga/output

# Record initial style count
INITIAL_STYLE_COUNT=$(get_style_count)
echo "$INITIAL_STYLE_COUNT" > /tmp/initial_style_count

# Ensure ne_countries layer exists (it should from env setup)
LAYER_CHECK=$(gs_rest_status "layers/ne:ne_countries.json")
if [ "$LAYER_CHECK" != "200" ]; then
    echo "WARNING: ne:ne_countries layer missing. Attempting to restore..."
    # Trigger env setup script logic if needed, but usually assumes env is healthy
fi

# Ensure Firefox is running and logged in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' &
    sleep 5
fi
wait_for_window "firefox\|mozilla" 60
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

echo "=== assign_alternate_styles task setup complete ==="