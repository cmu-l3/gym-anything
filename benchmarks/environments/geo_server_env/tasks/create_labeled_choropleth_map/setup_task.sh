#!/bin/bash
echo "=== Setting up create_labeled_choropleth_map task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists
mkdir -p /home/ga/output
chown ga:ga /home/ga/output

# Ensure GeoServer is running and verify 'ne' workspace and 'ne_countries' layer exist
# These should be created by the environment setup, but we verify here
echo "Verifying environment state..."
if ! gs_rest_status "workspaces/ne.json" | grep -q "200"; then
    echo "WARNING: 'ne' workspace not found. Task might fail."
fi
if ! gs_rest_status "layers/ne:ne_countries.json" | grep -q "200"; then
    echo "WARNING: 'ne:ne_countries' layer not found. Task might fail."
fi

# Record initial style count
INITIAL_STYLE_COUNT=$(get_style_count)
echo "$INITIAL_STYLE_COUNT" > /tmp/initial_style_count

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

echo "=== create_labeled_choropleth_map task setup complete ==="