#!/bin/bash
echo "=== Setting up Fix Missing CRS task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Create directories
INCOMING_DIR="/home/ga/GIS_Data/incoming"
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$INCOMING_DIR"
mkdir -p "$EXPORT_DIR"

# Clean previous task artifacts
rm -f "$EXPORT_DIR/sf_landmarks_wgs84.geojson" 2>/dev/null || true

# 1. Create source GeoJSON with real WGS84 coords
# Using 4 real landmarks in San Francisco
cat > /tmp/landmarks_source.geojson << EOF
{
"type": "FeatureCollection",
"name": "sf_landmarks",
"crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
"features": [
{ "type": "Feature", "properties": { "name": "Golden Gate Bridge South", "id": 1 }, "geometry": { "type": "Point", "coordinates": [ -122.4783, 37.8199 ] } },
{ "type": "Feature", "properties": { "name": "Coit Tower", "id": 2 }, "geometry": { "type": "Point", "coordinates": [ -122.4058, 37.8024 ] } },
{ "type": "Feature", "properties": { "name": "Mission Dolores", "id": 3 }, "geometry": { "type": "Point", "coordinates": [ -122.4269, 37.7641 ] } },
{ "type": "Feature", "properties": { "name": "Palace of Fine Arts", "id": 4 }, "geometry": { "type": "Point", "coordinates": [ -122.4484, 37.8029 ] } }
]
}
EOF

# 2. Convert to NAD83 / California Zone 3 (ftUS) - EPSG:2227
# We use ogr2ogr to perform the projection transformation
echo "Generating sabotaged shapefile..."
ogr2ogr -f "ESRI Shapefile" -t_srs EPSG:2227 "$INCOMING_DIR/sf_landmarks_missing_prj.shp" /tmp/landmarks_source.geojson

# 3. SABOTAGE: Delete the .prj file to remove CRS metadata
rm -f "$INCOMING_DIR/sf_landmarks_missing_prj.prj"
# Also remove .cpg to avoid any hints
rm -f "$INCOMING_DIR/sf_landmarks_missing_prj.cpg"

# 4. Create the surveyor notes
cat > "$INCOMING_DIR/surveyor_notes.txt" << EOF
Project: SF Historic Survey
Date: 2023-10-15
Surveyor: J. Doe

Data Specifications:
- Format: ESRI Shapefile
- Units: US Survey Feet
- Coordinate System: NAD83 / California Zone 3 (ftUS)
- Vertical Datum: NAVD88

Note: Please convert to WGS84 for the web portal.
EOF

# 5. Create a reference boundary to help the agent verify alignment visually
cat > "/home/ga/GIS_Data/sf_boundary_wgs84.geojson" << EOF
{
"type": "FeatureCollection",
"features": [{
"type": "Feature",
"properties": {"name": "SF Bounds"},
"geometry": {
"type": "Polygon",
"coordinates": [[
[-122.51, 37.70], [-122.35, 37.70], [-122.35, 37.84], [-122.51, 37.84], [-122.51, 37.70]
]]
}
}]
}
EOF

# Set permissions
chown -R ga:ga "$INCOMING_DIR"
chown -R ga:ga "$EXPORT_DIR"
chown ga:ga "/home/ga/GIS_Data/sf_boundary_wgs84.geojson"

# Ensure QGIS is clean
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS window
sleep 5
wait_for_window "QGIS" 45

# Maximize
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 2

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="