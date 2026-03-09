#!/bin/bash
echo "=== Setting up configure_workspace_service_availability task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure GeoServer is ready
wait_for_geoserver 60

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

# Reset 'ne' workspace settings to ensure a clean state (remove any overrides)
# We delete the workspace-specific service settings if they exist so they inherit from global
echo "Resetting workspace 'ne' service settings..."
curl -v -u "$GS_AUTH" -X DELETE "${GS_URL}/rest/services/wfs/workspaces/ne/settings" 2>/dev/null || true
curl -v -u "$GS_AUTH" -X DELETE "${GS_URL}/rest/services/wms/workspaces/ne/settings" 2>/dev/null || true
curl -v -u "$GS_AUTH" -X DELETE "${GS_URL}/rest/services/wcs/workspaces/ne/settings" 2>/dev/null || true

# Also ensure global services are enabled so disabling them locally is meaningful
# (This is the default state of the environment, but good to be sure)

# Generate integrity nonce
NONCE=$(generate_result_nonce)
echo "Result nonce: $NONCE"

# Snapshot access log for GUI interaction detection
snapshot_access_log

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== setup complete ==="