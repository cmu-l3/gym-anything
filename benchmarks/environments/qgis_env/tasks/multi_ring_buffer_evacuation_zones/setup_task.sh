#!/bin/bash
set -e
echo "=== Setting up multi-ring buffer evacuation zones task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure exports directory exists and is clean
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/evacuation_zones.geojson" 2>/dev/null || true
rm -f "$EXPORT_DIR/evacuation_zones.json" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"

# Record initial file counts
ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l > /tmp/initial_geojson_count.txt || echo "0" > /tmp/initial_geojson_count.txt

# Verify source data exists
if [ ! -f /home/ga/GIS_Data/sample_points.geojson ]; then
    echo "ERROR: sample_points.geojson not found! Recreating..."
    # Re-create if missing (fallback)
    mkdir -p /home/ga/GIS_Data
    cat > "/home/ga/GIS_Data/sample_points.geojson" << 'POINTSEOF'
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
POINTSEOF
    chown ga:ga "/home/ga/GIS_Data/sample_points.geojson"
fi

# Kill any existing QGIS instances
kill_qgis ga 2>/dev/null || true
sleep 2

# Launch QGIS
echo "Starting QGIS..."
# Using --noplugins to speed up start and reduce noise, but standard plugins like Processing are core
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

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
    DISPLAY=:1 wmctrl -r "QGIS" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any startup dialogs (tips, welcome page)
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="