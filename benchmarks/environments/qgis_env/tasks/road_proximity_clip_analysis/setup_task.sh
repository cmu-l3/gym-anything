#!/bin/bash
echo "=== Setting up road_proximity_clip_analysis task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure source data exists
POINTS_FILE="/home/ga/GIS_Data/sample_points.geojson"
LINES_FILE="/home/ga/GIS_Data/sample_lines.geojson"

if [ ! -f "$POINTS_FILE" ] || [ ! -f "$LINES_FILE" ]; then
    echo "ERROR: Source data missing!"
    exit 1
fi

# Clean up previous outputs
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/impacted_roads_500m.geojson" 2>/dev/null || true

# Record initial file state
echo "0" > /tmp/initial_file_exists.txt

# Ensure QGIS is running
if ! is_qgis_running; then
    echo "Starting QGIS..."
    su - ga -c "DISPLAY=:1 qgis &"
    wait_for_window "QGIS" 60
else
    echo "QGIS is already running"
fi

# Focus and maximize
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="