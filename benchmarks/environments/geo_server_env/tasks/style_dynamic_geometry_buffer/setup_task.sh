#!/bin/bash
echo "=== Setting up style_dynamic_geometry_buffer task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial style count
INITIAL_STYLE_COUNT=$(get_style_count)
echo "$INITIAL_STYLE_COUNT" > /tmp/initial_style_count

# Ensure ne_rivers exists
RIVERS_CHECK=$(gs_rest_status "workspaces/ne/layers/ne_rivers")
if [ "$RIVERS_CHECK" != "200" ]; then
    echo "ERROR: ne_rivers layer not found. Attempting to recover..."
    # Try to publish it if missing (recovery logic)
    # This relies on the store existing, which is standard in this env
    curl -u "$GS_AUTH" -X POST "${GS_URL}/rest/workspaces/ne/datastores/postgis_ne/featuretypes" \
        -H "Content-Type: application/json" \
        -d '{"featureType":{"name":"ne_rivers"}}' 2>/dev/null
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

# Generate integrity nonce
NONCE=$(generate_result_nonce)
echo "Result nonce: $NONCE"

# Snapshot access log for GUI interaction detection
snapshot_access_log

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== setup complete ==="