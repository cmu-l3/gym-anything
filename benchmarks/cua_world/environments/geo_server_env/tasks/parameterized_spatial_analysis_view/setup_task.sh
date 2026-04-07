#!/bin/bash
# Setup script for parameterized_spatial_analysis_view task

echo "=== Setting up parameterized_spatial_analysis_view ==="

source /workspace/scripts/task_utils.sh

# Verify GeoServer is accessible
if ! verify_geoserver_ready 60; then
    echo "ERROR: GeoServer not accessible"
    exit 1
fi

# Record baseline state
echo "Recording baseline state..."
INITIAL_WORKSPACE_COUNT=$(get_workspace_count)
INITIAL_LAYER_COUNT=$(get_layer_count)
INITIAL_STYLE_COUNT=$(get_style_count)

echo "$INITIAL_WORKSPACE_COUNT" > /tmp/initial_workspace_count
echo "$INITIAL_LAYER_COUNT" > /tmp/initial_layer_count
echo "$INITIAL_STYLE_COUNT" > /tmp/initial_style_count

echo "Baseline: $INITIAL_WORKSPACE_COUNT workspaces, $INITIAL_LAYER_COUNT layers, $INITIAL_STYLE_COUNT styles"

# Verify PostGIS tables exist with expected columns
echo "Verifying PostGIS data..."
COUNTRIES_COUNT=$(postgis_query "SELECT COUNT(*) FROM ne_countries;" 2>/dev/null || echo "0")
PLACES_COUNT=$(postgis_query "SELECT COUNT(*) FROM ne_populated_places;" 2>/dev/null || echo "0")
echo "ne_countries: $COUNTRIES_COUNT rows, ne_populated_places: $PLACES_COUNT rows"

# Verify key columns exist
echo "Verifying required columns..."
COUNTRIES_COLS=$(postgis_query "SELECT column_name FROM information_schema.columns WHERE table_name='ne_countries' AND column_name IN ('name','adm0_a3','continent','wkb_geometry','ogc_fid') ORDER BY column_name;" 2>/dev/null || echo "")
PLACES_COLS=$(postgis_query "SELECT column_name FROM information_schema.columns WHERE table_name='ne_populated_places' AND column_name IN ('name','pop_max','wkb_geometry','ogc_fid') ORDER BY column_name;" 2>/dev/null || echo "")
echo "ne_countries columns found: $COUNTRIES_COLS"
echo "ne_populated_places columns found: $PLACES_COLS"

# Quick spatial join test to confirm it works
SPATIAL_JOIN_TEST=$(postgis_query "SELECT COUNT(*) FROM ne_countries c JOIN ne_populated_places p ON ST_Contains(c.wkb_geometry, p.wkb_geometry) WHERE c.continent='Europe';" 2>/dev/null || echo "0")
echo "Spatial join test (Europe): $SPATIAL_JOIN_TEST city matches"

# Clean up any pre-existing spatial_analytics workspace (ensure clean start)
EXISTING_WS=$(gs_rest_get "workspaces/spatial_analytics.json" 2>/dev/null || echo "")
if echo "$EXISTING_WS" | grep -q '"name"'; then
    echo "WARNING: workspace 'spatial_analytics' already exists. Removing for clean setup..."
    curl -s -u "admin:Admin123!" -X DELETE \
        "http://localhost:8080/geoserver/rest/workspaces/spatial_analytics?recurse=true" \
        2>/dev/null || true
    sleep 2
fi

# Clean up any pre-existing global urban_density_gradient style
SLD_CHECK=$(gs_rest_status "styles/urban_density_gradient.json" 2>/dev/null || echo "404")
if [ "$SLD_CHECK" = "200" ]; then
    echo "Removing pre-existing global urban_density_gradient style..."
    curl -s -u "admin:Admin123!" -X DELETE \
        "http://localhost:8080/geoserver/rest/styles/urban_density_gradient?purge=true" \
        2>/dev/null || true
    sleep 1
fi

# Create output directory and clear stale files
mkdir -p /home/ga/output
chown ga:ga /home/ga/output
rm -f /home/ga/output/europe_density.png
rm -f /home/ga/output/asia_density.png

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
generate_result_nonce
snapshot_access_log

# Start Firefox and navigate to GeoServer
ensure_logged_in
take_screenshot /tmp/parameterized_spatial_analysis_view_start.png

echo "=== Setup Complete ==="
echo "Baseline: workspaces=$INITIAL_WORKSPACE_COUNT, layers=$INITIAL_LAYER_COUNT, styles=$INITIAL_STYLE_COUNT"
echo "PostGIS: $COUNTRIES_COUNT countries, $PLACES_COUNT places, spatial join test=$SPATIAL_JOIN_TEST"
