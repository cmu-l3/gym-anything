#!/bin/bash
echo "=== Setting up configure_kml_regionation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. Reset Layer Configuration (Critical for verification)
# ==============================================================================
echo "Resetting KML regionation settings for ne:ne_populated_places..."

# We use the REST API to forcibly unset/reset the regionation metadata
# Default strategy is usually 'best_guess' or 'geometry' with no attribute
RESET_PAYLOAD='{
  "layer": {
    "metadata": {
      "entry": [
        {"@key": "kml.regionateStrategy", "$": "geometry"},
        {"@key": "kml.regionateAttribute", "$": "name"}
      ]
    }
  }
}'

curl -u "$GS_AUTH" -X PUT \
    -H "Content-Type: application/json" \
    -d "$RESET_PAYLOAD" \
    "${GS_REST}/workspaces/ne/layers/ne_populated_places.json" 2>/dev/null

echo "Layer settings reset."

# Record initial state for debugging
INITIAL_CONFIG=$(gs_rest_get "workspaces/ne/layers/ne_populated_places.json")
echo "$INITIAL_CONFIG" > /tmp/initial_layer_config.json

# ==============================================================================
# 2. Prepare Application State
# ==============================================================================
# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' &
    sleep 5
fi

# Wait for window and ensure logged in
wait_for_window "firefox\|mozilla" 30
ensure_logged_in

# Focus Firefox and maximize
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

echo "=== configure_kml_regionation setup complete ==="