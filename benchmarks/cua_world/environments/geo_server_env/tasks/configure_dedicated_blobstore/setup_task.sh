#!/bin/bash
echo "=== Setting up configure_dedicated_blobstore task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for tile timestamp verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean state: Remove directory if it exists
TARGET_DIR="/home/ga/geoserver/cache/countries"
if [ -d "$TARGET_DIR" ]; then
    echo "Cleaning up existing target directory..."
    rm -rf "$TARGET_DIR"
fi

# Ensure GeoServer is running and logged in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' &
    sleep 5
fi
wait_for_window "firefox\|mozilla" 60
ensure_logged_in

# Navigate to Tile Caching section if possible, or just stay on dashboard
# Focusing Firefox
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

echo "=== configure_dedicated_blobstore task setup complete ==="