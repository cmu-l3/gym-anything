#!/bin/bash
echo "=== Setting up configure_workspace_virtual_wfs task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure GeoServer is ready
verify_geoserver_ready 60 || {
    echo "GeoServer not ready, waiting..."
    sleep 30
    verify_geoserver_ready 60
}

# 1. Ensure 'ne' workspace exists (it should from env setup)
WS_STATUS=$(gs_rest_status "workspaces/ne.json")
if [ "$WS_STATUS" != "200" ]; then
    echo "Creating 'ne' workspace..."
    curl -u "$GS_AUTH" -X POST -H "Content-type: application/json" \
      -d '{"workspace":{"name":"ne"}}' \
      "${GS_REST}/workspaces"
fi

# 2. CLEAR any existing workspace-specific WFS settings for 'ne'
# This ensures a clean state where the agent must create them
echo "Clearing existing workspace WFS settings..."
curl -s -u "$GS_AUTH" -X DELETE "${GS_REST}/services/wfs/workspaces/ne/settings" 2>/dev/null || true
sleep 2

# Verify they are gone (should return 404)
CLEAN_CHECK=$(gs_rest_status "services/wfs/workspaces/ne/settings.json")
echo "Workspace WFS settings status (expect 404): $CLEAN_CHECK"
echo "$CLEAN_CHECK" > /tmp/initial_wfs_status.txt

# 3. Clean up output files
rm -f /home/ga/ne_wfs_capabilities.xml
rm -f /home/ga/ne_countries_features.json

# 4. Open Firefox to GeoServer Admin
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

echo "=== Task setup complete ==="