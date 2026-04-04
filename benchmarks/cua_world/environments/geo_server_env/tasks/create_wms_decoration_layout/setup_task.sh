#!/bin/bash
echo "=== Setting up create_wms_decoration_layout task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# clean up any previous run artifacts on host
rm -f /home/ga/map_undecorated.png
rm -f /home/ga/map_decorated.png

# Clean up artifacts inside container (GeoServer data dir)
# Default GeoServer data dir in kartoza image is usually /opt/geoserver/data_dir
# We check GEOSERVER_DATA_DIR env var first
DATA_DIR=$(docker exec gs-app bash -c 'echo $GEOSERVER_DATA_DIR' 2>/dev/null)
if [ -z "$DATA_DIR" ]; then
    DATA_DIR="/opt/geoserver/data_dir"
fi

echo "Cleaning layout file in container at $DATA_DIR/layouts/report_map.xml..."
docker exec gs-app rm -f "$DATA_DIR/layouts/report_map.xml" 2>/dev/null || true

# Ensure Firefox is running and logged in (standard starting state)
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

# Snapshot access log for GUI interaction detection (though this task is CLI/HTTP heavy)
snapshot_access_log

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== create_wms_decoration_layout task setup complete ==="