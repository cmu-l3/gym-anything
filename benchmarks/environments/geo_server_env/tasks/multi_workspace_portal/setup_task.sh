#!/bin/bash
# Setup script for multi_workspace_portal task

echo "=== Setting up multi_workspace_portal ==="

source /workspace/scripts/task_utils.sh

if ! verify_geoserver_ready 60; then
    echo "ERROR: GeoServer not accessible"
    exit 1
fi

# Record baseline counts
INITIAL_WORKSPACE_COUNT=$(get_workspace_count)
INITIAL_LAYER_COUNT=$(get_layer_count)
INITIAL_STYLE_COUNT=$(get_style_count)
INITIAL_LG_COUNT=$(get_layergroup_count)

echo "$INITIAL_WORKSPACE_COUNT" > /tmp/initial_workspace_count
echo "$INITIAL_LAYER_COUNT" > /tmp/initial_layer_count
echo "$INITIAL_STYLE_COUNT" > /tmp/initial_style_count
echo "$INITIAL_LG_COUNT" > /tmp/initial_lg_count

echo "Baseline: ${INITIAL_WORKSPACE_COUNT} workspaces, ${INITIAL_LAYER_COUNT} layers, ${INITIAL_STYLE_COUNT} styles, ${INITIAL_LG_COUNT} layer groups"

# Clean up any pre-existing task-specific entities
echo "Cleaning up any pre-existing task entities..."
for WS in "infrastructure" "environment"; do
    curl -s -u "admin:Admin123!" -X DELETE \
        "http://localhost:8080/geoserver/rest/workspaces/${WS}?recurse=true" \
        2>/dev/null || true
done

for STYLE in "settlement_marker" "waterway_line"; do
    curl -s -u "admin:Admin123!" -X DELETE \
        "http://localhost:8080/geoserver/rest/styles/${STYLE}" 2>/dev/null || true
done

curl -s -u "admin:Admin123!" -X DELETE \
    "http://localhost:8080/geoserver/rest/layergroups/regional_portal" 2>/dev/null || true

sleep 2

# Verify source tables exist in PostGIS
echo "Verifying source tables..."
PP_COUNT=$(postgis_query "SELECT COUNT(*) FROM ne_populated_places;" 2>/dev/null || echo "0")
RIV_COUNT=$(postgis_query "SELECT COUNT(*) FROM ne_rivers;" 2>/dev/null || echo "0")
echo "ne_populated_places: $PP_COUNT rows, ne_rivers: $RIV_COUNT rows"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
generate_result_nonce
snapshot_access_log

ensure_logged_in
take_screenshot /tmp/multi_workspace_portal_start.png

echo "=== Setup Complete ==="
echo "Agent must create: 2 workspaces, 2 datastores, 2 layers, 2 styles, 1 layer group"
