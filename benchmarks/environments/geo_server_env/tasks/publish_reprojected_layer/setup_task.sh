#!/bin/bash
set -e
echo "=== Setting up task: publish_reprojected_layer ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure GeoServer is running and healthy
if ! verify_geoserver_ready 60; then
    echo "ERROR: GeoServer not ready, attempting restart..."
    cd /home/ga/geoserver && docker-compose restart gs-app
    sleep 30
    verify_geoserver_ready 120 || { echo "FATAL: GeoServer not responding"; exit 1; }
fi

# Verify prerequisite: ne workspace exists
WS_STATUS=$(gs_rest_status "workspaces/ne")
if [ "$WS_STATUS" != "200" ]; then
    echo "ERROR: Workspace 'ne' does not exist. Creating..."
    curl -s -u "$GS_AUTH" -X POST "${GS_REST}/workspaces" \
        -H "Content-Type: application/json" \
        -d '{"workspace":{"name":"ne"}}' || true
fi

# Verify prerequisite: postgis_ne data store exists
DS_STATUS=$(gs_rest_status "workspaces/ne/datastores/postgis_ne")
if [ "$DS_STATUS" != "200" ]; then
    echo "ERROR: Data store 'postgis_ne' does not exist"
    exit 1
fi

# Verify prerequisite: ne_countries feature type exists
FT_STATUS=$(gs_rest_status "workspaces/ne/datastores/postgis_ne/featuretypes/ne_countries")
if [ "$FT_STATUS" != "200" ]; then
    echo "ERROR: Feature type 'ne_countries' does not exist"
    exit 1
fi

# Clean up: remove ne_countries_3857 if it already exists (clean state)
EXISTING_STATUS=$(gs_rest_status "workspaces/ne/datastores/postgis_ne/featuretypes/ne_countries_3857")
if [ "$EXISTING_STATUS" = "200" ]; then
    echo "Removing existing ne_countries_3857 layer for clean state..."
    curl -s -u "$GS_AUTH" -X DELETE \
        "${GS_REST}/workspaces/ne/datastores/postgis_ne/featuretypes/ne_countries_3857?recurse=true" || true
    sleep 2
fi

# Record initial layer count for anti-gaming
INITIAL_LAYER_COUNT=$(get_layer_count)
echo "$INITIAL_LAYER_COUNT" > /tmp/initial_layer_count.txt
echo "Initial layer count: $INITIAL_LAYER_COUNT"

# Generate result nonce
NONCE=$(generate_result_nonce)
echo "Result nonce: $NONCE"

# Snapshot access log for GUI interaction detection
snapshot_access_log 2>/dev/null || true

# Start Firefox and navigate to GeoServer
pkill -f firefox 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 firefox --no-remote 'http://localhost:8080/geoserver/web/' > /dev/null 2>&1 &"
sleep 5

# Wait for Firefox window
wait_for_window "firefox\|Mozilla\|GeoServer" 30 || true

# Maximize and focus Firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Task: Create ne_countries_3857 layer with EPSG:3857 reprojection"
echo "Starting state: ne_countries exists in EPSG:4326, ne_countries_3857 does NOT exist"