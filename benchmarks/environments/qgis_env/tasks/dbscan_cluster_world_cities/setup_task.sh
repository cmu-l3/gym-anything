#!/bin/bash
echo "=== Setting up dbscan_cluster_world_cities task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if utils not present
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
DATA_DIR="/home/ga/GIS_Data"
mkdir -p "$DATA_DIR"
SHP_FILE="$DATA_DIR/ne_110m_populated_places.shp"

if [ ! -f "$SHP_FILE" ]; then
    echo "Downloading Natural Earth Populated Places..."
    # URL for 110m Cultural Vectors - Populated Places
    ZIP_URL="https://naciscdn.org/naturalearth/110m/cultural/ne_110m_populated_places.zip"
    
    # Download to temp location
    wget -q -O "$DATA_DIR/places.zip" "$ZIP_URL" || \
    curl -L -o "$DATA_DIR/places.zip" "$ZIP_URL"
    
    # Unzip
    unzip -o "$DATA_DIR/places.zip" -d "$DATA_DIR/"
    rm "$DATA_DIR/places.zip"
    
    # Ensure permissions
    chown -R ga:ga "$DATA_DIR"
fi

if [ ! -f "$SHP_FILE" ]; then
    echo "ERROR: Failed to prepare input data at $SHP_FILE"
    exit 1
fi

echo "Input data ready: $SHP_FILE"

# 2. Prepare Export Directory
EXPORT_DIR="$DATA_DIR/exports"
mkdir -p "$EXPORT_DIR"
# Remove any previous output to ensure clean state
rm -f "$EXPORT_DIR/clustered_cities.geojson" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"

# 3. Record Task Start State
# Record timestamp for anti-gaming (file must be newer than this)
date +%s > /tmp/task_start_timestamp

# Record initial file counts
ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l > /tmp/initial_export_count || echo "0" > /tmp/initial_export_count

# 4. Launch Application
# Kill any existing QGIS instances
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
# Launch QGIS maximizing chances of window appearing
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS to be ready
sleep 5
if wait_for_window "QGIS" 45; then
    echo "QGIS window detected"
    # Maximize window
    WID=$(get_qgis_window_id)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
else
    echo "WARNING: QGIS window not detected within timeout"
fi

# 5. Capture Initial State
sleep 2
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="