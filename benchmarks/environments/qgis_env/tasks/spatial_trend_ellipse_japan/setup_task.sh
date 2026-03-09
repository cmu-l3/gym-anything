#!/bin/bash
echo "=== Setting up spatial_trend_ellipse_japan task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if task_utils not available
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

# 1. Prepare Data
# Ensure the Natural Earth dataset is available
DATA_DIR="/home/ga/GIS_Data/natural_earth"
mkdir -p "$DATA_DIR"
SHP_FILE="$DATA_DIR/ne_110m_populated_places_simple.shp"

# If file doesn't exist, we might need to download it (though env usually has it)
# For robustness, we check and warn, or download if internet is allowed
if [ ! -f "$SHP_FILE" ]; then
    echo "Downloading dataset..."
    wget -q -O "/tmp/places.zip" "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_populated_places_simple.zip"
    unzip -o -q "/tmp/places.zip" -d "$DATA_DIR"
    rm -f "/tmp/places.zip"
    chown -R ga:ga "$DATA_DIR"
fi

# 2. Clean previous outputs
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/japan_urban_trend.geojson"
chown -R ga:ga "$EXPORT_DIR"

# 3. Record baseline state
date +%s > /tmp/task_start_timestamp

# 4. Reset Application State
kill_qgis ga 2>/dev/null || true
sleep 1

# 5. Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS to load
sleep 5
wait_for_window "QGIS" 45
sleep 3

# 6. Capture Initial State
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="