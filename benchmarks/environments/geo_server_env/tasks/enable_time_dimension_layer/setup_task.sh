#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Enable Time Dimension task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

GS_URL="http://localhost:8080/geoserver"
GS_AUTH="admin:Admin123!"

# Ensure GeoServer is ready
verify_geoserver_ready 120 || { echo "FATAL: GeoServer not ready"; exit 1; }

# ============================================================
# 1. Download/Install real earthquake data (PostGIS)
# ============================================================
echo "=== Setting up PostGIS data ==="

# Create table
docker exec -e PGPASSWORD=geoserver123 gs-postgis psql -U geoserver -h localhost -d gis -c "
DROP TABLE IF EXISTS earthquakes CASCADE;
CREATE TABLE earthquakes (
    gid SERIAL PRIMARY KEY,
    event_id VARCHAR(20),
    event_time TIMESTAMP WITH TIME ZONE,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    depth_km DOUBLE PRECISION,
    magnitude DOUBLE PRECISION,
    mag_type VARCHAR(10),
    place_desc VARCHAR(255),
    geom GEOMETRY(Point, 4326)
);
CREATE INDEX idx_earthquakes_geom ON earthquakes USING GIST(geom);
CREATE INDEX idx_earthquakes_time ON earthquakes (event_time);
" 2>/dev/null

# Insert Data (Hardcoded subset of real USGS data for reliability)
docker exec -e PGPASSWORD=geoserver123 gs-postgis psql -U geoserver -h localhost -d gis -c "
INSERT INTO earthquakes (event_id, event_time, latitude, longitude, depth_km, magnitude, mag_type, place_desc, geom) VALUES
('us7000lqmz','2024-01-01T09:23:14Z',7.563,126.579,62.87,5.7,'mww','9 km W of Mabini, Philippines',ST_SetSRID(ST_MakePoint(126.579,7.563),4326)),
('us7000lqn9','2024-01-01T15:02:51Z',-6.217,147.831,75.43,5.2,'mww','84 km NE of Finschhafen, Papua New Guinea',ST_SetSRID(ST_MakePoint(147.831,-6.217),4326)),
('us7000lr3s','2024-01-02T16:05:07Z',37.227,138.517,10.0,5.5,'mww','Noto Peninsula, Japan',ST_SetSRID(ST_MakePoint(138.517,37.227),4326)),
('us6000m0hl','2024-01-03T07:18:30Z',37.497,137.273,10.0,5.0,'mww','near coast of central Japan',ST_SetSRID(ST_MakePoint(137.273,37.497),4326)),
('us7000lr8f','2024-01-03T17:22:52Z',-4.711,153.228,80.0,5.4,'mww','New Ireland, Papua New Guinea',ST_SetSRID(ST_MakePoint(153.228,-4.711),4326)),
('us7000lral','2024-01-04T03:14:00Z',4.673,96.293,10.0,5.1,'mww','off west coast of northern Sumatra',ST_SetSRID(ST_MakePoint(96.293,4.673),4326)),
('us7000lrgk','2024-01-05T08:45:12Z',-18.483,167.839,10.0,5.3,'mww','Vanuatu',ST_SetSRID(ST_MakePoint(167.839,-18.483),4326)),
('us7000lrjz','2024-01-06T11:30:22Z',52.832,159.647,35.0,5.6,'mww','near east coast of Kamchatka',ST_SetSRID(ST_MakePoint(159.647,52.832),4326)),
('us7000lrnp','2024-01-07T23:59:44Z',-5.15,103.138,44.0,5.0,'mww','southern Sumatra, Indonesia',ST_SetSRID(ST_MakePoint(103.138,-5.15),4326)),
('us7000lrt5','2024-01-09T04:20:15Z',-10.888,165.174,10.0,5.5,'mww','Solomon Islands',ST_SetSRID(ST_MakePoint(165.174,-10.888),4326));
" 2>/dev/null

# ============================================================
# 2. Configure GeoServer (Workspace, Store, Layer)
# ============================================================
echo "=== creating workspace and layer ==="

# Create workspace 'seismic'
curl -s -u "$GS_AUTH" -X POST "${GS_URL}/rest/workspaces" \
    -H "Content-Type: application/json" \
    -d '{"workspace":{"name":"seismic"}}' >/dev/null

# Create PostGIS store
curl -s -u "$GS_AUTH" -X POST "${GS_URL}/rest/workspaces/seismic/datastores" \
    -H "Content-Type: application/json" \
    -d '{
        "dataStore": {
            "name": "postgis_seismic",
            "type": "PostGIS",
            "enabled": true,
            "connectionParameters": {
                "entry": [
                    {"@key":"host","$":"gs-postgis"},
                    {"@key":"port","$":"5432"},
                    {"@key":"database","$":"gis"},
                    {"@key":"schema","$":"public"},
                    {"@key":"user","$":"geoserver"},
                    {"@key":"passwd","$":"geoserver123"},
                    {"@key":"dbtype","$":"postgis"},
                    {"@key":"Expose primary keys","$":"true"}
                ]
            }
        }
    }' >/dev/null

# Publish layer (WITHOUT time dimension)
curl -s -u "$GS_AUTH" -X POST "${GS_URL}/rest/workspaces/seismic/datastores/postgis_seismic/featuretypes" \
    -H "Content-Type: application/json" \
    -d '{
        "featureType": {
            "name": "earthquakes",
            "title": "USGS Earthquake Events (Jan-Mar 2024)",
            "srs": "EPSG:4326",
            "nativeBoundingBox": { "minx": -180, "maxx": 180, "miny": -90, "maxy": 90, "crs": "EPSG:4326" },
            "latLonBoundingBox": { "minx": -180, "maxx": 180, "miny": -90, "maxy": 90, "crs": "EPSG:4326" }
        }
    }' >/dev/null

# ============================================================
# 3. Record Initial State (Anti-Gaming)
# ============================================================
# Check if time dimension is enabled (should be false/empty)
INITIAL_FT=$(curl -s -u "$GS_AUTH" "${GS_URL}/rest/workspaces/seismic/datastores/postgis_seismic/featuretypes/earthquakes.json")

# Use python to safely parse JSON and check for time dimension
HAS_TIME=$(echo "$INITIAL_FT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    md = d.get('featureType',{}).get('metadata',{}).get('entry',[])
    if isinstance(md, dict): md = [md]
    found = False
    for e in md:
        if e.get('@key') == 'time' and e.get('dimensionInfo',{}).get('enabled') == True:
            found = True
    print('ENABLED' if found else 'NOT_ENABLED')
except:
    print('NOT_ENABLED')
" 2>/dev/null)

echo "$HAS_TIME" > /tmp/initial_time_dimension_state.txt
echo "Initial time dimension state: $HAS_TIME"

# Generate nonce for result integrity
NONCE=$(generate_result_nonce)

# Snapshot access log for GUI interaction detection
snapshot_access_log

# ============================================================
# 4. Launch Browser
# ============================================================
echo "=== Launching Firefox ==="
pkill -f firefox 2>/dev/null || true
su - ga -c "DISPLAY=:1 firefox --no-remote 'http://localhost:8080/geoserver/web/' &"
wait_for_window "firefox\|mozilla" 30
ensure_logged_in
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="