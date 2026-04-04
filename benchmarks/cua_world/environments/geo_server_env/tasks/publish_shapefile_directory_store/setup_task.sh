#!/bin/bash
echo "=== Setting up publish_shapefile_directory_store task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial state
INITIAL_WS_COUNT=$(get_workspace_count)
echo "$INITIAL_WS_COUNT" > /tmp/initial_workspace_count

INITIAL_STORE_COUNT=$(get_datastore_count)
echo "$INITIAL_STORE_COUNT" > /tmp/initial_store_count

# Verify source data exists on host
if [ ! -d "/home/ga/natural_earth" ]; then
    echo "ERROR: Source data /home/ga/natural_earth missing"
    # Attempt to restore from backup or fail
    mkdir -p /home/ga/natural_earth
    # (Assuming environment setup put files there, but checking just in case)
fi

# Clean up any previous attempts (anti-gaming)
# Remove the container directory if it exists to force the agent to create it
docker exec gs-app rm -rf /opt/geoserver/data_dir/shp_data 2>/dev/null || true

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

# Generate integrity nonce
NONCE=$(generate_result_nonce)
echo "Result nonce: $NONCE"

# Snapshot access log for GUI interaction detection
snapshot_access_log

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== publish_shapefile_directory_store task setup complete ==="