#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up update_layer_metadata task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify GeoServer is running
if ! verify_geoserver_ready 60; then
    echo "ERROR: GeoServer not ready"
    exit 1
fi

# Record initial state of the layer for anti-gaming verification
# We need to know what it looked like BEFORE the agent touched it
INITIAL_FT=$(gs_rest_get "workspaces/ne/datastores/postgis_ne/featuretypes/ne_countries.json" 2>/dev/null)
echo "$INITIAL_FT" > /tmp/initial_layer_state.json

# Extract specific initial fields for easy comparison later
INITIAL_TITLE=$(echo "$INITIAL_FT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('featureType',{}).get('title',''))" 2>/dev/null || echo "")
echo "$INITIAL_TITLE" > /tmp/initial_layer_title.txt

INITIAL_LAYER=$(gs_rest_get "layers/ne:ne_countries.json" 2>/dev/null)
INITIAL_QUERYABLE=$(echo "$INITIAL_LAYER" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('layer',{}).get('queryable', 'not_set'))" 2>/dev/null || echo "not_set")
echo "$INITIAL_QUERYABLE" > /tmp/initial_queryable.txt

echo "Initial State Recorded:"
echo "  Title: $INITIAL_TITLE"
echo "  Queryable: $INITIAL_QUERYABLE"

# Generate verification nonce
NONCE=$(generate_result_nonce)
echo "Result nonce: $NONCE"

# Ensure Firefox is running and pointing to GeoServer
pkill -f firefox || true
sleep 2
su - ga -c "DISPLAY=:1 firefox --no-remote 'http://localhost:8080/geoserver/web/' &"
sleep 8

# Wait for Firefox window
wait_for_window "firefox\|mozilla\|geoserver" 30 || {
    echo "WARNING: Firefox window not detected"
}

# Maximize Firefox
focus_firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Snapshot access log for GUI interaction detection
snapshot_access_log

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="