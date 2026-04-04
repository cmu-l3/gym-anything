#!/bin/bash
echo "=== Setting up create_sensor_network_layer task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if utils not available
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
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

# Ensure data directory exists
DATA_DIR="/home/ga/GIS_Data"
mkdir -p "$DATA_DIR"
chown ga:ga "$DATA_DIR"

# CLEAN START: Remove the target file if it exists to ensure agent creates it fresh
TARGET_FILE="$DATA_DIR/sensor_network.gpkg"
if [ -f "$TARGET_FILE" ]; then
    echo "Removing existing target file: $TARGET_FILE"
    rm -f "$TARGET_FILE"
fi

# Record start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Kill any running QGIS instances to ensure clean state
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS window
echo "Waiting for QGIS window..."
wait_for_window "QGIS" 45
sleep 3

# Maximize window
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Target file should be created at: $TARGET_FILE"