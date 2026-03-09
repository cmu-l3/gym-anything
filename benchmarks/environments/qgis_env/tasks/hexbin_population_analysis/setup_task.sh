#!/bin/bash
echo "=== Setting up hexbin_population_analysis task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
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
DATA_DIR="/home/ga/GIS_Data/ne_10m_populated_places"
mkdir -p "$DATA_DIR"
SHP_FILE="$DATA_DIR/ne_10m_populated_places.shp"

if [ ! -f "$SHP_FILE" ]; then
    echo "Downloading Natural Earth Populated Places dataset..."
    # Using a reliable mirror or source. If this fails, we generate a mock for reliability in this env,
    # but the task spec requires real data. We assume internet access or pre-cached data.
    # For robustness in this script, we'll try download, and if it fails, we abort or warn.
    
    ZIP_FILE="$DATA_DIR/places.zip"
    wget -q -O "$ZIP_FILE" "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_populated_places.zip" || \
    wget -q -O "$ZIP_FILE" "https://github.com/nvkelso/natural-earth-vector/raw/master/10m_cultural/ne_10m_populated_places.zip"
    
    if [ -f "$ZIP_FILE" ]; then
        unzip -o -q "$ZIP_FILE" -d "$DATA_DIR"
        rm "$ZIP_FILE"
    else
        echo "ERROR: Failed to download dataset. Check internet connection."
        # Fallback: Create a dummy shapefile if download fails (to prevent task crash, though verification will fail)
        # In a real scenario, we would exit 1.
        exit 1
    fi
fi

chown -R ga:ga "/home/ga/GIS_Data"

# 2. Clean previous outputs
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/europe_hexbin_population.geojson" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"

# 3. Record initial state
date +%s > /tmp/task_start_timestamp

# 4. Start QGIS
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS
sleep 5
wait_for_window "QGIS" 60
sleep 3

# Maximize
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="