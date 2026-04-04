#!/bin/bash
echo "=== Setting up digitize_connected_route_snapping task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure source data exists
SOURCE_DATA="/home/ga/GIS_Data/sample_points.geojson"
if [ ! -f "$SOURCE_DATA" ]; then
    echo "Restoring sample point data..."
    # Re-create if missing (using the data from setup_qgis.sh logic)
    cat > "$SOURCE_DATA" << 'EOF'
{
  "type": "FeatureCollection",
  "name": "sample_points",
  "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
  "features": [
    { "type": "Feature", "properties": { "id": 1, "name": "Point A", "elevation": 100 }, "geometry": { "type": "Point", "coordinates": [-122.4, 37.6] } },
    { "type": "Feature", "properties": { "id": 2, "name": "Point B", "elevation": 150 }, "geometry": { "type": "Point", "coordinates": [-122.3, 37.7] } },
    { "type": "Feature", "properties": { "id": 3, "name": "Point C", "elevation": 200 }, "geometry": { "type": "Point", "coordinates": [-122.1, 37.65] } }
  ]
}
EOF
    chown ga:ga "$SOURCE_DATA"
fi

# Remove any previous attempt
rm -f "/home/ga/GIS_Data/power_line.gpkg"
rm -f "/home/ga/GIS_Data/power_line.gpkg-journal"

# Kill any running QGIS
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS with the sample data loaded
echo "Launching QGIS with sample points..."
# We pass the file as an argument so it loads on startup
su - ga -c "DISPLAY=:1 qgis '$SOURCE_DATA' > /tmp/qgis_task.log 2>&1 &"

# Wait for window
wait_for_window "QGIS" 60
sleep 5

# Maximize window
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any startup dialogs/tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="