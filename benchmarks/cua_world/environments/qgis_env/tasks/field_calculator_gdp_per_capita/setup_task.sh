#!/bin/bash
set -e
echo "=== Setting up Field Calculator GDP Per Capita task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure export directory exists and is clean
mkdir -p /home/ga/GIS_Data/exports
rm -f /home/ga/GIS_Data/exports/countries_gdp_per_capita.csv
rm -f /home/ga/GIS_Data/exports/*.csv 2>/dev/null || true

# Prepare Data Directory
NE_DIR="/home/ga/GIS_Data/natural_earth"
mkdir -p "$NE_DIR"

# Download Natural Earth 110m countries if not present
SHP_FILE="$NE_DIR/ne_110m_admin_0_countries.shp"
if [ ! -f "$SHP_FILE" ]; then
    echo "Downloading Natural Earth dataset..."
    NE_ZIP="/tmp/ne_110m_admin_0_countries.zip"
    
    # Try primary source
    if ! curl -L -o "$NE_ZIP" --connect-timeout 30 --max-time 120 "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip"; then
        echo "Primary source failed, trying mirror..."
        # Fallback mirror or alternate source (using known stable link structure)
        curl -L -o "$NE_ZIP" "https://www.naturalearthdata.com/http//www.naturalearthdata.com/download/110m/cultural/ne_110m_admin_0_countries.zip"
    fi
    
    echo "Extracting data..."
    unzip -o -q "$NE_ZIP" -d "$NE_DIR/"
    rm -f "$NE_ZIP"
else
    echo "Dataset already present."
fi

# Set permissions
chown -R ga:ga /home/ga/GIS_Data

# Ensure QGIS is running
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis --noversioncheck > /dev/null 2>&1 &"

# Wait for QGIS to load
wait_for_window "QGIS" 40

# Maximize window
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any startup dialogs (like tips)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Data location: $SHP_FILE"