#!/bin/bash
echo "=== Setting up river_floodplain_transects task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Data Directory
DATA_DIR="/home/ga/GIS_Data/natural_earth"
mkdir -p "$DATA_DIR"
mkdir -p "/home/ga/GIS_Data/exports"

# 2. Download/Check Data
# Natural Earth Rivers & Lake Centerlines (10m)
SHP_FILE="$DATA_DIR/ne_10m_rivers_lake_centerlines.shp"

if [ ! -f "$SHP_FILE" ]; then
    echo "Downloading Natural Earth Rivers data..."
    # URL for 10m physical vectors - rivers
    # Using a stable mirror or direct link
    wget -q -O "$DATA_DIR/rivers.zip" "https://naciscdn.org/naturalearth/10m/physical/ne_10m_rivers_lake_centerlines.zip"
    
    if [ -f "$DATA_DIR/rivers.zip" ]; then
        unzip -o -q "$DATA_DIR/rivers.zip" -d "$DATA_DIR"
        rm "$DATA_DIR/rivers.zip"
        echo "Data downloaded and extracted."
    else
        echo "ERROR: Failed to download data."
        exit 1
    fi
else
    echo "Data already exists at $SHP_FILE"
fi

# Ensure permissions
chown -R ga:ga "/home/ga/GIS_Data"

# 3. Clean previous outputs
rm -f "/home/ga/GIS_Data/exports/danube_transects.geojson" 2>/dev/null
rm -f "/home/ga/GIS_Data/exports/danube_transects.qmd" 2>/dev/null # Remove potential metadata sidecars

# 4. Record Initial State
# Count existing geojson files to ensure we detect new ones
ls -1 /home/ga/GIS_Data/exports/*.geojson 2>/dev/null | wc -l > /tmp/initial_export_count

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Launch QGIS
# Kill any existing instances first
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for window
wait_for_window "QGIS" 45

# Maximize
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="