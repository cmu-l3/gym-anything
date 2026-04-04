#!/bin/bash
set -e
echo "=== Setting up Select by Expression Export task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Prepare Data Directory
DATA_DIR="/home/ga/GIS_Data/ne_110m_populated_places_simple"
mkdir -p "$DATA_DIR"
mkdir -p "/home/ga/GIS_Data/exports"
chown -R ga:ga "/home/ga/GIS_Data"

# 3. Download Natural Earth Dataset (Real Data)
SHP_FILE="$DATA_DIR/ne_110m_populated_places_simple.shp"
ZIP_FILE="/tmp/ne_places.zip"

if [ ! -f "$SHP_FILE" ]; then
    echo "Downloading Natural Earth Populated Places..."
    # Try primary source
    if ! wget -q -O "$ZIP_FILE" "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_populated_places_simple.zip"; then
        echo "Primary download failed, trying mirror..."
        # Backup mirror (GitHub raw or similar reliable source)
        wget -q -O "$ZIP_FILE" "https://github.com/nvkelso/natural-earth-vector/raw/master/zips/110m_cultural/ne_110m_populated_places_simple.zip"
    fi
    
    # Extract
    unzip -o -q "$ZIP_FILE" -d "$DATA_DIR"
    rm -f "$ZIP_FILE"
    
    # Ensure permissions
    chown -R ga:ga "$DATA_DIR"
fi

# Verify data exists
if [ ! -f "$SHP_FILE" ]; then
    echo "ERROR: Failed to prepare dataset."
    exit 1
fi
echo "Dataset ready at: $SHP_FILE"

# 4. Clean previous exports
rm -f "/home/ga/GIS_Data/exports/major_megacities.geojson"
rm -f "/home/ga/GIS_Data/exports/major_megacities.json"

# 5. Ensure QGIS is running
if ! is_qgis_running; then
    echo "Starting QGIS..."
    su - ga -c "DISPLAY=:1 qgis > /dev/null 2>&1 &"
    sleep 5
fi

# Wait for QGIS to be ready
wait_for_window "QGIS" 40

# 6. Configure Window (Maximize)
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="