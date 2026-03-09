#!/bin/bash
echo "=== Setting up implement_isolated_workspace task ==="

source /workspace/scripts/task_utils.sh

# Record initial state
INITIAL_WS_COUNT=$(get_workspace_count)
echo "$INITIAL_WS_COUNT" > /tmp/initial_ws_count

# Ensure PostGIS has the required data (ne_rivers)
# The environment setup imports this, but we verify it here
echo "Verifying PostGIS data..."
RIVERS_COUNT=$(postgis_query "SELECT count(*) FROM ne_rivers" 2>/dev/null || echo "0")
if [ "$RIVERS_COUNT" = "0" ] || [ -z "$RIVERS_COUNT" ]; then
    echo "WARNING: ne_rivers table missing or empty. Attempting re-import..."
    # Fallback import command just in case
    if [ -f "/home/ga/natural_earth/ne_110m_rivers_lake_centerlines.shp" ]; then
        docker cp "/home/ga/natural_earth/ne_110m_rivers_lake_centerlines.shp" gs-postgis:/tmp/rivers.shp
        docker cp "/home/ga/natural_earth/ne_110m_rivers_lake_centerlines.shx" gs-postgis:/tmp/rivers.shx
        docker cp "/home/ga/natural_earth/ne_110m_rivers_lake_centerlines.dbf" gs-postgis:/tmp/rivers.dbf
        docker exec gs-postgis ogr2ogr -f "PostgreSQL" \
            "PG:host=localhost dbname=gis user=geoserver password=geoserver123" \
            "/tmp/rivers.shp" -nln "ne_rivers" -overwrite -a_srs "EPSG:4326"
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

echo "=== Setup complete ==="