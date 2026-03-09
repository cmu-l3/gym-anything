#!/bin/bash
set -e
echo "=== Setting up configure_scale_dependent_labeling ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure GeoServer is ready
if ! verify_geoserver_ready 60; then
    echo "ERROR: GeoServer not ready"
    exit 1
fi

# Ensure logged in state
ensure_logged_in

# Reset the layer style to 'point' (default) to ensure clean state
# This removes any previous work if the task was restarted
echo "Resetting ne_populated_places style..."
curl -u "$GS_AUTH" -X PUT "${GS_URL}/rest/workspaces/ne/layers/ne_populated_places" \
    -H "Content-Type: application/json" \
    -d '{ "layer": { "defaultStyle": { "name": "point" } } }' 2>/dev/null || true

# Delete the target style if it exists
echo "Cleaning up old style..."
curl -u "$GS_AUTH" -X DELETE "${GS_URL}/rest/workspaces/ne/styles/scaled_cities?recurse=true" 2>/dev/null || true

# Focus Firefox and navigate to Styles page to save some navigation clicks
focus_firefox
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type --delay 20 "${GS_URL}/web/?wicket:bookmarkablePage=:org.geoserver.web.data.style.StylePage"
DISPLAY=:1 xdotool key Return
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="