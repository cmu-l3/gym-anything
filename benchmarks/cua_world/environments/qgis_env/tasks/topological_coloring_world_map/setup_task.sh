#!/bin/bash
echo "=== Setting up topological_coloring_world_map task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Data
DATA_DIR="/home/ga/GIS_Data"
SOURCE_FILE="$DATA_DIR/ne_110m_admin_0_countries.shp"
SOURCE_ZIP="$DATA_DIR/ne_110m_admin_0_countries.zip"

mkdir -p "$DATA_DIR"
mkdir -p "$DATA_DIR/exports"
mkdir -p "$DATA_DIR/projects"

# Download Natural Earth countries if missing
if [ ! -f "$SOURCE_FILE" ]; then
    echo "Downloading world countries dataset..."
    wget -q -O "$SOURCE_ZIP" "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip"
    
    if [ -f "$SOURCE_ZIP" ]; then
        unzip -o "$SOURCE_ZIP" -d "$DATA_DIR"
        rm "$SOURCE_ZIP"
        echo "Data extracted to $DATA_DIR"
    else
        echo "ERROR: Failed to download dataset"
        # Create a fallback dummy file if download fails (to prevent immediate crash, though task will fail)
        touch "$SOURCE_FILE"
    fi
fi

# Ensure permissions
chown -R ga:ga "$DATA_DIR"

# 2. Clean previous artifacts
rm -f "$DATA_DIR/exports/world_colored.geojson" 2>/dev/null || true
rm -f "$DATA_DIR/projects/world_map_colored.qgz" 2>/dev/null || true
rm -f "$DATA_DIR/projects/world_map_colored.qgs" 2>/dev/null || true

# 3. Record initial state
date +%s > /tmp/task_start_timestamp

# 4. Setup QGIS
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for window
sleep 5
wait_for_window "QGIS" 45
sleep 3

# 5. Capture initial state
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="