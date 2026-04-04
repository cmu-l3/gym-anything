#!/bin/bash
set -e
echo "=== Setting up Points Along Lines task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure exports directory exists and is clean of previous results
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/inspection_points.geojson" 2>/dev/null || true
rm -f "$EXPORT_DIR/inspection_points.json" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"

# Record initial state
ls -la "$EXPORT_DIR" > /tmp/initial_exports_state.txt 2>/dev/null || true
echo "0" > /tmp/initial_output_exists.txt

# Verify input data exists
if [ ! -f "/home/ga/GIS_Data/sample_lines.geojson" ]; then
    echo "ERROR: Input sample_lines.geojson not found!"
    # Try to regenerate it if missing (using the logic from setup_qgis.sh)
    echo "Regenerating sample data..."
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

echo "Input data verified: $(wc -c < /home/ga/GIS_Data/sample_lines.geojson) bytes"

# Kill any existing QGIS
kill_qgis ga 2>/dev/null || true
sleep 2

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS window
wait_for_window "QGIS" 40
sleep 3

# Maximize and focus QGIS
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 2

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Input: /home/ga/GIS_Data/sample_lines.geojson"
echo "Expected output: /home/ga/GIS_Data/exports/inspection_points.geojson"