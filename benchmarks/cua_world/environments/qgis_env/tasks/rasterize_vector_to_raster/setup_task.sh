#!/bin/bash
set -e
echo "=== Setting up rasterize_vector_to_raster task ==="

source /workspace/scripts/task_utils.sh

# 1. Environment Preparation
# Ensure export and project directories exist and are clean
su - ga -c "mkdir -p /home/ga/GIS_Data/exports"
su - ga -c "mkdir -p /home/ga/GIS_Data/projects"

# Remove artifacts from previous runs
rm -f /home/ga/GIS_Data/exports/polygon_raster.tif 2>/dev/null || true
rm -f /home/ga/GIS_Data/exports/polygon_raster.* 2>/dev/null || true
rm -f /home/ga/GIS_Data/projects/rasterize_project.qgs 2>/dev/null || true
rm -f /home/ga/GIS_Data/projects/rasterize_project.qgz 2>/dev/null || true

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 2. Data Verification
# Ensure input data exists
if [ ! -f /home/ga/GIS_Data/sample_polygon.geojson ]; then
    echo "ERROR: sample_polygon.geojson not found! Regenerating..."
    # Regenerate if missing (fallback from setup_qgis.sh)
    cat > "/home/ga/GIS_Data/sample_polygon.geojson" << 'GEOJSONEOF'
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
    chown ga:ga "/home/ga/GIS_Data/sample_polygon.geojson"
fi

# 3. Application Startup
# Kill any existing QGIS processes
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis --noversioncheck --skipbadlayers > /tmp/qgis_launch.log 2>&1 &"

# Wait for QGIS window
if wait_for_window "QGIS" 40; then
    echo "QGIS started successfully"
else
    echo "WARNING: QGIS window not detected within timeout"
fi

# Maximize and focus QGIS
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any startup dialogs (Esc key)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 4. Evidence Collection
# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Input: /home/ga/GIS_Data/sample_polygon.geojson"