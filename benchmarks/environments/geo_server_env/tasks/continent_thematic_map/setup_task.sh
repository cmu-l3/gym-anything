#!/bin/bash
# Setup script for continent_thematic_map task

echo "=== Setting up continent_thematic_map ==="

source /workspace/scripts/task_utils.sh

# Verify GeoServer is accessible
echo "Verifying GeoServer accessibility..."
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

# Verify ne_countries table exists in PostGIS
echo "Verifying ne_countries table exists in PostGIS..."
NE_COUNT=$(postgis_query "SELECT COUNT(*) FROM ne_countries;" 2>/dev/null || echo "0")
echo "ne_countries row count: $NE_COUNT"

if [ "$NE_COUNT" = "0" ] || [ -z "$NE_COUNT" ]; then
    echo "WARNING: ne_countries table appears empty. Attempting re-import..."
    # Try to reimport from shapefiles if available
    if [ -f "/workspace/data/natural_earth/ne_110m_admin_0_countries.shp" ]; then
        docker exec -e PGPASSWORD=geoserver123 gs-postgis ogr2ogr \
            -f "PostgreSQL" "PG:host=localhost dbname=gis user=geoserver password=geoserver123" \
            /workspace/data/natural_earth/ne_110m_admin_0_countries.shp \
            -nln ne_countries -t_srs EPSG:4326 -nlt PROMOTE_TO_MULTI -overwrite 2>/dev/null || true
    fi
fi

# Also verify the ne_countries has a continent column
CONTINENT_CHECK=$(postgis_query "SELECT DISTINCT continent FROM ne_countries LIMIT 5;" 2>/dev/null || echo "")
echo "Sample continents: $CONTINENT_CHECK"

# Verify that 'regional_atlas' workspace does NOT already exist (it shouldn't, but check)
EXISTING_WS=$(gs_rest_get "workspaces/regional_atlas.json" 2>/dev/null || echo "")
if echo "$EXISTING_WS" | grep -q '"name"'; then
    echo "WARNING: workspace 'regional_atlas' already exists. Removing for clean setup..."
    curl -s -u "admin:Admin123!" -X DELETE \
        "http://localhost:8080/geoserver/rest/workspaces/regional_atlas?recurse=true" 2>/dev/null || true
    sleep 2
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Generate result nonce for integrity verification
generate_result_nonce

# Snapshot access log for GUI interaction detection
snapshot_access_log

# Start Firefox and navigate to GeoServer
echo "Starting Firefox and navigating to GeoServer..."
ensure_logged_in

# Take initial screenshot
take_screenshot /tmp/continent_thematic_map_start.png

echo "=== Setup Complete ==="
echo "Baseline: workspaces=$INITIAL_WORKSPACE_COUNT, layers=$INITIAL_LAYER_COUNT, styles=$INITIAL_STYLE_COUNT"
