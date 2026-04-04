#!/bin/bash
echo "=== Setting up publish_shapefile_layer task ==="

source /workspace/scripts/task_utils.sh

# Record initial state
INITIAL_LAYER_COUNT=$(get_layer_count)
echo "$INITIAL_LAYER_COUNT" > /tmp/initial_layer_count
echo "Initial layer count: $INITIAL_LAYER_COUNT"

INITIAL_STORE_COUNT=$(get_datastore_count)
echo "$INITIAL_STORE_COUNT" > /tmp/initial_store_count
echo "Initial store count: $INITIAL_STORE_COUNT"

# Verify PostGIS table exists
TABLE_CHECK=$(postgis_query "SELECT COUNT(*) FROM ne_countries" 2>/dev/null || echo "0")
echo "ne_countries record count: $TABLE_CHECK"

if [ "$TABLE_CHECK" = "0" ] || [ -z "$TABLE_CHECK" ]; then
    echo "WARNING: ne_countries table is empty or missing. Attempting reimport..."
    if [ -f /home/ga/natural_earth/ne_110m_admin_0_countries.shp ]; then
        for ext in shp shx dbf prj cpg; do
            if [ -f "/home/ga/natural_earth/ne_110m_admin_0_countries.${ext}" ]; then
                docker cp "/home/ga/natural_earth/ne_110m_admin_0_countries.${ext}" gs-postgis:/tmp/
            fi
        done
        docker exec gs-postgis ogr2ogr \
            -f "PostgreSQL" \
            "PG:host=localhost dbname=gis user=geoserver password=geoserver123" \
            "/tmp/ne_110m_admin_0_countries.shp" \
            -nln "ne_countries" \
            -overwrite \
            -nlt PROMOTE_TO_MULTI \
            -lco GEOMETRY_NAME=geom \
            -lco FID=gid \
            -a_srs "EPSG:4326" 2>/dev/null || true
    fi
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

echo "=== publish_shapefile_layer task setup complete ==="
