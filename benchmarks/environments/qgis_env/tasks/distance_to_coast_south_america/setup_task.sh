#!/bin/bash
echo "=== Setting up distance_to_coast_south_america task ==="

source /workspace/scripts/task_utils.sh

# Data directory setup
DATA_DIR="/home/ga/GIS_Data/natural_earth"
mkdir -p "$DATA_DIR"

# Download required Natural Earth data if not present
# Populated Places
if [ ! -f "$DATA_DIR/ne_10m_populated_places_simple.shp" ]; then
    echo "Downloading populated places..."
    wget -q -O "$DATA_DIR/places.zip" "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_populated_places_simple.zip"
    unzip -o -q "$DATA_DIR/places.zip" -d "$DATA_DIR"
    rm "$DATA_DIR/places.zip"
fi

# Coastline
if [ ! -f "$DATA_DIR/ne_10m_coastline.shp" ]; then
    echo "Downloading coastline..."
    wget -q -O "$DATA_DIR/coast.zip" "https://naciscdn.org/naturalearth/10m/physical/ne_10m_coastline.zip"
    unzip -o -q "$DATA_DIR/coast.zip" -d "$DATA_DIR"
    rm "$DATA_DIR/coast.zip"
fi

# Ensure permissions
chown -R ga:ga "/home/ga/GIS_Data"

# Clean previous exports
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/sa_cities_coast_dist.csv" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"

# Kill running QGIS to ensure clean state
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for window
wait_for_window "QGIS" 60

# Maximize
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Record start time
date +%s > /tmp/task_start_timestamp

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="