#!/bin/bash
echo "=== Setting up restrict_wfs_transactions task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure GeoServer is running
if ! verify_geoserver_ready 60; then
    echo "Starting GeoServer..."
    # The container entrypoint usually handles this, but we ensure it's up
    sleep 10
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

# Reset Service Security to default (if possible) to ensure clean state
# We can't easily reset via REST API as Security API might be locked or complex
# We assume the environment starts with default insecure/open settings or basic settings.
# We will record the initial state of the services.properties file if it exists.

SECURITY_DIR="/home/ga/geoserver/data_dir/security"
if [ -f "$SECURITY_DIR/services.properties" ]; then
    cp "$SECURITY_DIR/services.properties" /tmp/initial_services.properties
else
    echo "# No initial services.properties found" > /tmp/initial_services.properties
fi

# Generate integrity nonce
NONCE=$(generate_result_nonce)
echo "Result nonce: $NONCE"

# Snapshot access log for GUI interaction detection
snapshot_access_log

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== setup complete ==="