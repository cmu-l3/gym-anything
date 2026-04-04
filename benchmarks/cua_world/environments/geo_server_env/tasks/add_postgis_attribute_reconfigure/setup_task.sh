#!/bin/bash
echo "=== Setting up add_postgis_attribute_reconfigure task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists
mkdir -p /home/ga/output
chown ga:ga /home/ga/output

# 1. Verify PostGIS connection and table existence
echo "Checking PostGIS table..."
TABLE_EXISTS=$(postgis_query "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'ne_countries');")

if [ "$TABLE_EXISTS" != "t" ]; then
    echo "Restoring ne_countries table..."
    # Import logic from shared utils or manual
    if [ -f /home/ga/natural_earth/ne_110m_admin_0_countries.shp ]; then
        docker cp "/home/ga/natural_earth/ne_110m_admin_0_countries.shp" gs-postgis:/tmp/
        docker cp "/home/ga/natural_earth/ne_110m_admin_0_countries.shx" gs-postgis:/tmp/
        docker cp "/home/ga/natural_earth/ne_110m_admin_0_countries.dbf" gs-postgis:/tmp/
        docker cp "/home/ga/natural_earth/ne_110m_admin_0_countries.prj" gs-postgis:/tmp/
        
        docker exec gs-postgis ogr2ogr \
            -f "PostgreSQL" \
            "PG:host=localhost dbname=gis user=geoserver password=geoserver123" \
            "/tmp/ne_110m_admin_0_countries.shp" \
            -nln "ne_countries" \
            -overwrite \
            -nlt PROMOTE_TO_MULTI \
            -lco GEOMETRY_NAME=geom \
            -lco FID=gid \
            -a_srs "EPSG:4326"
    fi
fi

# 2. Ensure clean state: Drop pop_density if it exists from previous run
echo "Cleaning up potential stale columns..."
postgis_query "ALTER TABLE ne_countries DROP COLUMN IF EXISTS pop_density;" >/dev/null 2>&1

# 3. Record initial columns for verification
echo "Recording initial columns..."
INITIAL_COLUMNS=$(postgis_query "SELECT column_name FROM information_schema.columns WHERE table_name='ne_countries';" | tr '\n' ',' )
echo "$INITIAL_COLUMNS" > /tmp/initial_columns.txt

# 4. Ensure GeoServer layer is published initially (without the column)
# This ensures the agent is starting from a working state
# (Assuming setup_geoserver.sh already published it, but we can verify)
LAYER_STATUS=$(gs_rest_status "layers/ne:ne_countries.json")
if [ "$LAYER_STATUS" != "200" ]; then
    echo "WARNING: ne:ne_countries not published. Attempting to publish..."
    # (Simplified publication logic relying on existing store)
    curl -u admin:Admin123! -X POST "http://localhost:8080/geoserver/rest/workspaces/ne/datastores/postgis_ne/featuretypes" \
        -H "Content-Type: application/json" \
        -d '{"featureType":{"name":"ne_countries"}}'
fi

# 5. Open terminal/browser
# We open a terminal for the DB work and browser for GeoServer
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=100x30 &"
fi

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' &"
    sleep 5
fi

wait_for_window "firefox\|mozilla" 30
ensure_logged_in
focus_firefox

# Snapshot logs for GUI interaction check
snapshot_access_log

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="