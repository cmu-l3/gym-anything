#!/bin/bash
echo "=== Setting up line_polygon_intersection_overlay task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if utils not loaded
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
if [ ! -f "/home/ga/GIS_Data/sample_lines.geojson" ] || [ ! -f "/home/ga/GIS_Data/sample_polygon.geojson" ]; then
    echo "ERROR: Input data files missing in /home/ga/GIS_Data/"
    # Attempt to regenerate if missing (safety net)
    echo "Regenerating sample data..."
    /workspace/scripts/setup_qgis.sh
fi

# Clean up any previous output
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/roads_by_zone.geojson" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR" 2>/dev/null || true

# Record baseline state
ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l > /tmp/initial_export_count || echo "0" > /tmp/initial_export_count
echo "Initial export count: $(cat /tmp/initial_export_count)"

# Record timestamp for anti-gaming
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

# Maximize window explicitly
WID=$(DISPLAY=:1 wmctrl -l | grep -i "QGIS" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="