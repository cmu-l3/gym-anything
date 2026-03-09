#!/bin/bash
echo "=== Setting up exclusion_zone_difference_overlay task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if task_utils not loaded correctly
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi
if ! type wait_for_window &>/dev/null; then
    wait_for_window() {
        local pattern="$1"; local timeout=${2:-30}; local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$pattern" && return 0
            sleep 1; elapsed=$((elapsed + 1))
        done
        return 1
    }
fi

# Verify source data exists
if [ ! -f "/home/ga/GIS_Data/sample_polygon.geojson" ]; then
    echo "ERROR: sample_polygon.geojson not found!"
    exit 1
fi
if [ ! -f "/home/ga/GIS_Data/sample_points.geojson" ]; then
    echo "ERROR: sample_points.geojson not found!"
    exit 1
fi

# Clean up any previous output
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/developable_areas.geojson" 2>/dev/null || true
# Clean intermediate files if they exist from previous runs (to ensure clean slate)
rm -f "$EXPORT_DIR/buffered_points.geojson" 2>/dev/null || true
rm -f "$EXPORT_DIR/reprojected_*.geojson" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR" 2>/dev/null || true

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Kill any running QGIS instances to ensure clean start
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS window to appear
sleep 5
wait_for_window "QGIS" 40

# Allow initialization
sleep 5

# Maximize window
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="