#!/bin/bash
# Setup script for gwc_tile_cache_seeding task

echo "=== Setting up gwc_tile_cache_seeding ==="

source /workspace/scripts/task_utils.sh

if ! verify_geoserver_ready 60; then
    echo "ERROR: GeoServer not accessible"
    exit 1
fi

# Record baseline GWC configuration for ne:ne_countries
echo "Recording baseline GWC state..."

# Check if GWC layer already exists for ne:ne_countries
GWC_LAYER_JSON=$(curl -s -u "admin:Admin123!" \
    "http://localhost:8080/geoserver/gwc/rest/layers/ne:ne_countries.json" 2>/dev/null || echo "")
echo "Current GWC ne:ne_countries config: $(echo "$GWC_LAYER_JSON" | head -c 200)"

# Save initial state to tmp files
echo "$GWC_LAYER_JSON" > /tmp/initial_gwc_layer.json

# Cancel any ongoing seed operations for ne:ne_countries (clean start)
echo "Ensuring no active seed jobs..."
curl -s -u "admin:Admin123!" -X POST \
    "http://localhost:8080/geoserver/gwc/rest/seed/ne:ne_countries.json" \
    -H "Content-Type: application/json" \
    -d '{"seedRequest":{"type":"truncate","gridSetId":"EPSG:4326","format":"image/png","zoomStart":0,"zoomStop":3}}' \
    2>/dev/null || true
sleep 2

# Verify ne:ne_countries layer exists in GeoServer
NE_COUNTRIES=$(gs_rest_get "layers/ne:ne_countries.json" 2>/dev/null || echo "")
if ! echo "$NE_COUNTRIES" | grep -q '"name"'; then
    echo "WARNING: ne:ne_countries layer not found in GeoServer. Ensure it is published."
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
generate_result_nonce
snapshot_access_log

ensure_logged_in
take_screenshot /tmp/gwc_tile_cache_seeding_start.png

echo "=== Setup Complete ==="
echo "Agent must: configure GWC gridsets + format + metatile for ne:ne_countries, then trigger tile seeding"
