#!/bin/bash
echo "=== Setting up network_analysis_shortest_path task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions for standalone testing
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi

# Ensure data directories exist
mkdir -p /home/ga/GIS_Data/exports
chown -R ga:ga /home/ga/GIS_Data

# Generate Road Network Data (Synthetic Topology)
# We create a simple 1x1 degree square with a diagonal
# Use simple coordinates for easy geometric verification
# A (0,0) -> B (0,1) -> C (1,1) (Manhattan path, len=2)
# A (0,0) -> C (1,1) (Diagonal path, len=1.414)
# We shift coordinates to a real place (e.g., off coast of Africa) to avoid "invalid projection" warnings if QGIS is picky,
# or just use simple generic coordinates. Let's use 0,0 to 1,1.
# Format: GeoJSON

cat > /home/ga/GIS_Data/road_network.geojson << 'EOF'
{
"type": "FeatureCollection",
"name": "road_network",
"crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
"features": [
{ "type": "Feature", "properties": { "id": 1, "type": "road", "speed": 50 }, "geometry": { "type": "LineString", "coordinates": [ [0.0, 0.0], [0.0, 1.0] ] } },
{ "type": "Feature", "properties": { "id": 2, "type": "road", "speed": 50 }, "geometry": { "type": "LineString", "coordinates": [ [0.0, 1.0], [1.0, 1.0] ] } },
{ "type": "Feature", "properties": { "id": 3, "type": "road", "speed": 50 }, "geometry": { "type": "LineString", "coordinates": [ [1.0, 1.0], [1.0, 0.0] ] } },
{ "type": "Feature", "properties": { "id": 4, "type": "road", "speed": 50 }, "geometry": { "type": "LineString", "coordinates": [ [1.0, 0.0], [0.0, 0.0] ] } },
{ "type": "Feature", "properties": { "id": 5, "type": "highway", "speed": 90 }, "geometry": { "type": "LineString", "coordinates": [ [0.0, 0.0], [1.0, 1.0] ] } }
]
}
EOF

# Generate Stops Data (Start and End)
cat > /home/ga/GIS_Data/logistics_stops.geojson << 'EOF'
{
"type": "FeatureCollection",
"name": "logistics_stops",
"crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
"features": [
{ "type": "Feature", "properties": { "id": 1, "name": "Warehouse", "type": "start" }, "geometry": { "type": "Point", "coordinates": [ 0.0, 0.0 ] } },
{ "type": "Feature", "properties": { "id": 2, "name": "Customer", "type": "end" }, "geometry": { "type": "Point", "coordinates": [ 1.0, 1.0 ] } }
]
}
EOF

# Fix permissions
chown ga:ga /home/ga/GIS_Data/road_network.geojson
chown ga:ga /home/ga/GIS_Data/logistics_stops.geojson

# Clean up previous exports
rm -f /home/ga/GIS_Data/exports/delivery_route.geojson 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time.txt

# Start QGIS
kill_qgis ga 2>/dev/null || true
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS
sleep 5
wait_for_window "QGIS" 45

# Maximize
DISPLAY=:1 wmctrl -r "QGIS" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="