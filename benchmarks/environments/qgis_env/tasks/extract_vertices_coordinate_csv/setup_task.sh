#!/bin/bash
set -e
echo "=== Setting up Extract Vertices task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/GIS_Data/exports
mkdir -p /home/ga/GIS_Data/projects

# Remove any pre-existing output files (clean slate)
rm -f /home/ga/GIS_Data/exports/polygon_vertices.csv
rm -f /home/ga/GIS_Data/projects/vertex_extraction.qgs
rm -f /home/ga/GIS_Data/projects/vertex_extraction.qgz

# Set permissions
chown -R ga:ga /home/ga/GIS_Data/exports
chown -R ga:ga /home/ga/GIS_Data/projects

# Ensure input data exists
SAMPLE_FILE="/home/ga/GIS_Data/sample_polygon.geojson"
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Creating input polygon data..."
    cat > "$SAMPLE_FILE" << 'GEOJSONEOF'
{
  "type": "FeatureCollection",
  "name": "sample_polygon",
  "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
  "features": [
    {
      "type": "Feature",
      "properties": { "id": 1, "name": "Area A", "area_sqkm": 10.5 },
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[-122.5, 37.5], [-122.5, 37.8], [-122.2, 37.8], [-122.2, 37.5], [-122.5, 37.5]]]
      }
    },
    {
      "type": "Feature",
      "properties": { "id": 2, "name": "Area B", "area_sqkm": 8.2 },
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[-122.2, 37.5], [-122.2, 37.8], [-121.9, 37.8], [-121.9, 37.5], [-122.2, 37.5]]]
      }
    }
  ]
}
GEOJSONEOF
    chown ga:ga "$SAMPLE_FILE"
fi

# Kill any existing QGIS instances
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Starting QGIS..."
su - ga -c "DISPLAY=:1 qgis --noversioncheck --skipbadlayers > /tmp/qgis_launch.log 2>&1 &"

# Wait for QGIS window
wait_for_window "QGIS" 40

# Maximize and focus QGIS
sleep 2
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any startup dialogs (like "Tips")
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="