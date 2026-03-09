#!/bin/bash
echo "=== Setting up Print Layout Map Composition task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if utils not available
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi

# 1. Clean up previous runs
PROJECT_DIR="/home/ga/GIS_Data/projects"
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$PROJECT_DIR"
mkdir -p "$EXPORT_DIR"

rm -f "$PROJECT_DIR/bay_area_map.qgs" "$PROJECT_DIR/bay_area_map.qgz" 2>/dev/null || true
rm -f "$EXPORT_DIR/bay_area_map.png" "$EXPORT_DIR/bay_area_map.pdf" 2>/dev/null || true

# 2. Verify source data exists
if [ ! -f "/home/ga/GIS_Data/sample_polygon.geojson" ] || [ ! -f "/home/ga/GIS_Data/sample_points.geojson" ]; then
    echo "ERROR: Source data missing!"
    exit 1
fi

# 3. Record baseline state
date +%s > /tmp/task_start_timestamp
echo "0" > /tmp/initial_project_count
ls -1 "$PROJECT_DIR"/*.qG* 2>/dev/null | wc -l > /tmp/initial_project_count || echo "0" > /tmp/initial_project_count

# 4. Ensure QGIS is running fresh
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for window
sleep 5
wait_for_window "QGIS" 60
sleep 3

# Maximize
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="