#!/bin/bash
echo "=== Setting up extract_scenic_roads_spatial_query task ==="

source /workspace/scripts/task_utils.sh

# Directory setup
NE_DIR="/home/ga/GIS_Data/natural_earth"
mkdir -p "$NE_DIR"
mkdir -p "/home/ga/GIS_Data/exports"

# Download Natural Earth Data
# Roads (10m)
if [ ! -f "$NE_DIR/ne_10m_roads.shp" ]; then
    echo "Downloading NE 10m Roads..."
    curl -L -o "$NE_DIR/ne_10m_roads.zip" "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_roads.zip"
    unzip -o "$NE_DIR/ne_10m_roads.zip" -d "$NE_DIR/"
fi

# Parks (10m)
if [ ! -f "$NE_DIR/ne_10m_parks_and_protected_lands.shp" ]; then
    echo "Downloading NE 10m Parks..."
    curl -L -o "$NE_DIR/ne_10m_parks_and_protected_lands.zip" "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_parks_and_protected_lands.zip"
    unzip -o "$NE_DIR/ne_10m_parks_and_protected_lands.zip" -d "$NE_DIR/"
fi

# Set permissions
chown -R ga:ga "/home/ga/GIS_Data"

# Clean previous output
rm -f "/home/ga/GIS_Data/exports/scenic_roads.geojson"

# Record start time
date +%s > /tmp/task_start_timestamp

# Ensure QGIS is not running (clean start)
kill_qgis ga 2>/dev/null || true
sleep 2

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS
wait_for_window "QGIS" 60
sleep 5

# Maximize window
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="