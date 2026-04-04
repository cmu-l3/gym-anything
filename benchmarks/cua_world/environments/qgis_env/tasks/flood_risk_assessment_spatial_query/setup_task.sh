#!/bin/bash
echo "=== Setting up flood_risk_assessment_spatial_query task ==="

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
DATA_DIR="/home/ga/GIS_Data/liechtenstein"
mkdir -p "$DATA_DIR"
mkdir -p "/home/ga/GIS_Data/exports"
chown -R ga:ga "/home/ga/GIS_Data"

# Check if data exists, otherwise download
if [ ! -f "$DATA_DIR/gis_osm_waterways_free_1.shp" ] || [ ! -f "$DATA_DIR/gis_osm_places_free_1.shp" ]; then
    echo "Downloading Liechtenstein OpenStreetMap data..."
    # URL for Liechtenstein shapefiles from Geofabrik
    DATA_URL="https://download.geofabrik.de/europe/liechtenstein-latest-free.shp.zip"
    
    # Download with retry
    wget -q --show-progress -O "$DATA_DIR/data.zip" "$DATA_URL" || {
        echo "Primary download failed, trying backup source..."
        # If geofabrik fails, we could use a backup, but for now we'll just fail hard if networking is down
        # In a real production environment, we'd have a local mirror.
        exit 1
    }
    
    echo "Extracting data..."
    unzip -o -q "$DATA_DIR/data.zip" -d "$DATA_DIR"
    rm "$DATA_DIR/data.zip"
    
    # Ensure permissions
    chown -R ga:ga "$DATA_DIR"
fi

# Verify critical files exist
if [ ! -f "$DATA_DIR/gis_osm_waterways_free_1.shp" ]; then
    echo "ERROR: Failed to prepare waterways shapefile"
    exit 1
fi

# 2. Cleanup previous runs
rm -f "/home/ga/GIS_Data/exports/at_risk_towns.geojson" 2>/dev/null || true

# 3. Launch Application
# Kill any running QGIS
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for window
sleep 5
wait_for_window "QGIS" 60
sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "QGIS" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# 4. Record Initial State
# Timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Data location: $DATA_DIR"
echo "Task: Identify towns within 1km of the Rhine river"