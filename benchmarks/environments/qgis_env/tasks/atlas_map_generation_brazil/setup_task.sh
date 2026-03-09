#!/bin/bash
echo "=== Setting up atlas_map_generation_brazil task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Natural Earth data exists
DATA_DIR="/home/ga/GIS_Data/natural_earth"
SHP_FILE="$DATA_DIR/ne_110m_admin_0_countries.shp"

if [ ! -f "$SHP_FILE" ]; then
    echo "Downloading Natural Earth countries dataset..."
    mkdir -p "$DATA_DIR"
    
    # Download zip
    curl -L -o "$DATA_DIR/ne_110m_admin_0_countries.zip" \
        "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip"
    
    # Unzip
    unzip -o "$DATA_DIR/ne_110m_admin_0_countries.zip" -d "$DATA_DIR/"
    
    # Cleanup
    rm "$DATA_DIR/ne_110m_admin_0_countries.zip"
    
    # Verify
    if [ ! -f "$SHP_FILE" ]; then
        echo "ERROR: Failed to prepare shapefile."
        exit 1
    fi
fi

# Set permissions
chown -R ga:ga "/home/ga/GIS_Data"

# 2. Clean previous outputs
rm -f "/home/ga/GIS_Data/exports/brazil_atlas_map.pdf" 2>/dev/null || true
rm -f "/home/ga/GIS_Data/projects/atlas_project.qgz" 2>/dev/null || true
rm -f "/home/ga/GIS_Data/projects/atlas_project.qgs" 2>/dev/null || true

# 3. Record baseline state
echo "0" > /tmp/initial_pdf_count
ls -1 "/home/ga/GIS_Data/exports/"*.pdf 2>/dev/null | wc -l > /tmp/initial_pdf_count || true

# 4. Record timestamp
date +%s > /tmp/task_start_timestamp

# 5. Kill any running QGIS
kill_qgis ga 2>/dev/null || true
sleep 1

# 6. Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

sleep 5
wait_for_window "QGIS" 30
sleep 3

# 7. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="