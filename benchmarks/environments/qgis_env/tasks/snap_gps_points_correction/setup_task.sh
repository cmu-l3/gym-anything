#!/bin/bash
echo "=== Setting up snap_gps_points_correction task ==="

source /workspace/scripts/task_utils.sh

# Ensure GIS Data directory exists
mkdir -p /home/ga/GIS_Data/exports

# Check if sample_lines exists (from env setup), if not, recreate it
if [ ! -f "/home/ga/GIS_Data/sample_lines.geojson" ]; then
    echo "Recreating sample_lines.geojson..."
    cat > "/home/ga/GIS_Data/sample_lines.geojson" << 'LINESEOF'
{
  "type": "FeatureCollection",
  "name": "sample_lines",
  "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
  "features": [
    { "type": "Feature", "properties": { "id": 1, "name": "Road 1", "type": "highway" }, "geometry": { "type": "LineString", "coordinates": [[-122.5, 37.5], [-122.3, 37.6], [-122.1, 37.7]] } },
    { "type": "Feature", "properties": { "id": 2, "name": "Road 2", "type": "secondary" }, "geometry": { "type": "LineString", "coordinates": [[-122.4, 37.5], [-122.4, 37.8]] } }
  ]
}
LINESEOF
    chown ga:ga "/home/ga/GIS_Data/sample_lines.geojson"
fi

# Generate noisy GPS points
# These are points slightly offset from the lines defined above
echo "Generating noisy_gps_points.geojson..."
cat > "/home/ga/GIS_Data/noisy_gps_points.geojson" << 'POINTSEOF'
{
  "type": "FeatureCollection",
  "name": "noisy_gps_points",
  "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
  "features": [
    { "type": "Feature", "properties": { "id": 1, "truck_id": "T-101" }, "geometry": { "type": "Point", "coordinates": [-122.499, 37.501] } },
    { "type": "Feature", "properties": { "id": 2, "truck_id": "T-101" }, "geometry": { "type": "Point", "coordinates": [-122.401, 37.551] } },
    { "type": "Feature", "properties": { "id": 3, "truck_id": "T-102" }, "geometry": { "type": "Point", "coordinates": [-122.302, 37.599] } },
    { "type": "Feature", "properties": { "id": 4, "truck_id": "T-103" }, "geometry": { "type": "Point", "coordinates": [-122.402, 37.651] } },
    { "type": "Feature", "properties": { "id": 5, "truck_id": "T-103" }, "geometry": { "type": "Point", "coordinates": [-122.399, 37.750] } },
    { "type": "Feature", "properties": { "id": 6, "truck_id": "T-104" }, "geometry": { "type": "Point", "coordinates": [-122.101, 37.699] } }
  ]
}
POINTSEOF
chown ga:ga "/home/ga/GIS_Data/noisy_gps_points.geojson"

# Clean up any previous output
rm -f "/home/ga/GIS_Data/exports/snapped_points.geojson" 2>/dev/null || true

# Record baseline state
echo "0" > /tmp/initial_export_count
if [ -d "/home/ga/GIS_Data/exports" ]; then
    ls -1 "/home/ga/GIS_Data/exports"/*.geojson 2>/dev/null | wc -l > /tmp/initial_export_count || echo "0" > /tmp/initial_export_count
fi

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Kill any running QGIS
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS window
sleep 5
wait_for_window "QGIS" 45
sleep 3

# Maximize
wid=$(get_qgis_window_id)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="