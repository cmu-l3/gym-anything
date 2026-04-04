#!/bin/bash
echo "=== Setting up Airport Proximity Modeler task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Directories
DATA_DIR="/home/ga/GIS_Data"
SOURCE_DIR="$DATA_DIR/source"
MODELS_DIR="$DATA_DIR/models"
EXPORTS_DIR="$DATA_DIR/exports"

mkdir -p "$SOURCE_DIR" "$MODELS_DIR" "$EXPORTS_DIR"

# 2. Download Real Data (Natural Earth)
# Airports
if [ ! -f "$SOURCE_DIR/ne_10m_airports.shp" ]; then
    echo "Downloading Airports data..."
    wget -q -O "$SOURCE_DIR/airports.zip" "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_airports.zip"
    unzip -q -o "$SOURCE_DIR/airports.zip" -d "$SOURCE_DIR/"
    rm "$SOURCE_DIR/airports.zip"
fi

# Urban Areas
if [ ! -f "$SOURCE_DIR/ne_10m_urban_areas.shp" ]; then
    echo "Downloading Urban Areas data..."
    wget -q -O "$SOURCE_DIR/urban.zip" "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_urban_areas.zip"
    unzip -q -o "$SOURCE_DIR/urban.zip" -d "$SOURCE_DIR/"
    rm "$SOURCE_DIR/urban.zip"
fi

# Set permissions
chown -R ga:ga "$DATA_DIR"

# 3. Clean previous artifacts
rm -f "$MODELS_DIR/airport_impact.model3"
rm -f "$EXPORTS_DIR/urban_noise_zones.geojson"

# 4. Record Initial State
date +%s > /tmp/task_start_time.txt
ls -1 "$MODELS_DIR" | wc -l > /tmp/initial_model_count.txt

# 5. Launch QGIS
kill_qgis ga 2>/dev/null || true
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS
if wait_for_window "QGIS" 60; then
    echo "QGIS started successfully."
    sleep 5
    # Maximize
    WID=$(get_qgis_window_id)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
    fi
else
    echo "WARNING: QGIS window not found."
fi

# 6. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="