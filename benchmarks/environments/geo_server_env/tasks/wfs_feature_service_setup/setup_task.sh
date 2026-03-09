#!/bin/bash
# Setup script for wfs_feature_service_setup task

echo "=== Setting up wfs_feature_service_setup ==="

source /workspace/scripts/task_utils.sh

if ! verify_geoserver_ready 60; then
    echo "ERROR: GeoServer not accessible"
    exit 1
fi

# Record baseline WFS settings
echo "Recording baseline WFS settings..."
WFS_JSON=$(gs_rest_get "services/wfs/settings.json" 2>/dev/null || echo "{}")
WFS_ENABLED=$(echo "$WFS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('wfs',{}).get('enabled',False)).lower())" 2>/dev/null || echo "false")
WFS_TITLE=$(echo "$WFS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('wfs',{}).get('title',''))" 2>/dev/null || echo "")
WFS_MAX=$(echo "$WFS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('wfs',{}).get('maxFeatures',0))" 2>/dev/null || echo "0")

echo "$WFS_ENABLED" > /tmp/initial_wfs_enabled
echo "$WFS_TITLE" > /tmp/initial_wfs_title
echo "$WFS_MAX" > /tmp/initial_wfs_max

# Record baseline layer/style counts
INITIAL_LAYER_COUNT=$(get_layer_count)
INITIAL_STYLE_COUNT=$(get_style_count)
echo "$INITIAL_LAYER_COUNT" > /tmp/initial_layer_count
echo "$INITIAL_STYLE_COUNT" > /tmp/initial_style_count

echo "Baseline WFS: enabled=$WFS_ENABLED, title='$WFS_TITLE', maxFeatures=$WFS_MAX"
echo "Baseline: $INITIAL_LAYER_COUNT layers, $INITIAL_STYLE_COUNT styles"

# Verify ne_populated_places exists in PostGIS
echo "Verifying ne_populated_places in PostGIS..."
PP_COUNT=$(postgis_query "SELECT COUNT(*) FROM ne_populated_places;" 2>/dev/null || echo "0")
echo "ne_populated_places row count: $PP_COUNT"

# Verify the ne workspace exists (should be set up by post_start)
NE_WS=$(gs_rest_get "workspaces/ne.json" 2>/dev/null || echo "")
if ! echo "$NE_WS" | grep -q '"name"'; then
    echo "WARNING: 'ne' workspace not found. This is required for the task."
fi

# Check that ne datastore exists (should be there from environment setup)
NE_DS_JSON=$(gs_rest_get "workspaces/ne/datastores.json" 2>/dev/null || echo "")
NE_DS_NAME=$(echo "$NE_DS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
stores = d.get('dataStores', {}).get('dataStore', [])
if not isinstance(stores, list): stores = [stores] if stores else []
for s in stores:
    print(s.get('name', ''))
    break
" 2>/dev/null || echo "")
echo "NE PostGIS datastore: '$NE_DS_NAME'"

# Disable WFS at task start so agent must explicitly enable it (prevents baseline false positive)
echo "Disabling WFS to ensure clean baseline..."
curl -s -u "admin:Admin123!" -X PUT \
    "http://localhost:8080/geoserver/rest/services/wfs/settings" \
    -H "Content-Type: application/json" \
    -d '{"wfs": {"enabled": false}}' 2>/dev/null || true
sleep 1
echo "false" > /tmp/initial_wfs_enabled

# Remove any pre-existing major_cities SQL view layer (clean start)
curl -s -u "admin:Admin123!" -X DELETE \
    "http://localhost:8080/geoserver/rest/workspaces/ne/datastores/postgis_natural_earth/featuretypes/major_cities?recurse=true" \
    2>/dev/null || true
sleep 1

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
generate_result_nonce
snapshot_access_log

ensure_logged_in
take_screenshot /tmp/wfs_feature_service_setup_start.png

echo "=== Setup Complete ==="
