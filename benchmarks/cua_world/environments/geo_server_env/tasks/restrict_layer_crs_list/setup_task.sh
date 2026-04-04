#!/bin/bash
echo "=== Setting up restrict_layer_crs_list task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Reset ne_countries layer configuration to default (empty responseSRS)
# This ensures the layer advertises ALL CRS by default at start
echo "Resetting ne_countries configuration..."
curl -u "$GS_AUTH" -X PUT "${GS_URL}/rest/workspaces/ne/datastores/postgis_ne/featuretypes/ne_countries.json" \
    -H "Content-Type: application/json" \
    -d '{
        "featureType": {
            "responseSRS": { "string": [] }
        }
    }' 2>/dev/null

# 2. Record initial state
INITIAL_CONFIG=$(gs_rest_get "workspaces/ne/datastores/postgis_ne/featuretypes/ne_countries.json")
echo "$INITIAL_CONFIG" > /tmp/initial_config.json

# 3. Ensure Firefox is running and logged in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' &
    sleep 5
fi
wait_for_window "firefox\|mozilla" 30
ensure_logged_in

# 4. Focus Firefox
focus_firefox
DISPLAY=:1 xdotool mousemove 960 540 click 1
sleep 1

# 5. Snapshot access log for GUI interaction detection
snapshot_access_log

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== restrict_layer_crs_list task setup complete ==="