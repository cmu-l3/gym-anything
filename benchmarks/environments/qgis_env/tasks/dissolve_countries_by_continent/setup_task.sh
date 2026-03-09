#!/bin/bash
set -e
echo "=== Setting up dissolve_countries_by_continent task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Directories
DATA_DIR="/home/ga/GIS_Data/natural_earth"
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$DATA_DIR"
mkdir -p "$EXPORT_DIR"
chown -R ga:ga "/home/ga/GIS_Data"

# 2. Download Real Data (Natural Earth)
# URL for 1:110m Cultural Vectors - Admin 0 - Countries
NE_URL="https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip"
SHP_FILE="$DATA_DIR/ne_110m_admin_0_countries.shp"

if [ ! -f "$SHP_FILE" ]; then
    echo "Downloading Natural Earth Countries dataset..."
    # Try curl first, then wget
    if command -v curl >/dev/null; then
        curl -L -o "$DATA_DIR/countries.zip" "$NE_URL"
    else
        wget -O "$DATA_DIR/countries.zip" "$NE_URL"
    fi

    if [ -f "$DATA_DIR/countries.zip" ]; then
        echo "Extracting data..."
        unzip -o "$DATA_DIR/countries.zip" -d "$DATA_DIR"
        rm "$DATA_DIR/countries.zip"
    else
        echo "ERROR: Failed to download dataset. Check network connection."
        # Fail gracefully implies we might not be able to proceed, but we'll try to let the agent fail naturally if files missing
    fi
else
    echo "Dataset already exists."
fi

# Ensure permissions
chown -R ga:ga "$DATA_DIR"

# 3. Clean previous outputs
rm -f "$EXPORT_DIR/continents_dissolved.geojson" 2>/dev/null || true
rm -f "$EXPORT_DIR/continents_dissolved.json" 2>/dev/null || true

# 4. Record Initial State
# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Launch Application
if ! is_qgis_running; then
    echo "Starting QGIS..."
    su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"
    
    # Wait for window
    if wait_for_window "QGIS" 60; then
        echo "QGIS started successfully"
    else
        echo "WARNING: QGIS window not detected, but process might be running"
    fi
else
    echo "QGIS is already running"
fi

# 6. Configure Window
# Give QGIS time to settle
sleep 5
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 7. Initial Evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="