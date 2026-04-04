#!/bin/bash
echo "=== Setting up extract_index_contours_elevation task ==="

source /workspace/scripts/task_utils.sh

# Define paths
DATA_DIR="/home/ga/GIS_Data/raster"
INPUT_FILE="$DATA_DIR/srtm_41_19.tif"
EXPORT_DIR="/home/ga/GIS_Data/exports"

# Create directories
mkdir -p "$DATA_DIR"
mkdir -p "$EXPORT_DIR"

# Clean up previous outputs
rm -f "$EXPORT_DIR/index_contours.geojson" 2>/dev/null || true

# Prepare Input Data (Real SRTM Data)
if [ ! -f "$INPUT_FILE" ]; then
    echo "Downloading SRTM data..."
    # URL for QGIS Training Data (Official Source)
    URL="https://github.com/qgis/QGIS-Training-Data/raw/master/exercise_data/raster/SRTM/srtm_41_19.tif"
    
    if command -v wget >/dev/null; then
        wget -q -O "$INPUT_FILE" "$URL"
    elif command -v curl >/dev/null; then
        curl -L -o "$INPUT_FILE" "$URL"
    else
        echo "Error: Neither wget nor curl found."
        exit 1
    fi
    
    # Check if download succeeded
    if [ ! -f "$INPUT_FILE" ] || [ $(stat -c%s "$INPUT_FILE") -lt 1000 ]; then
        echo "Download failed or file too small. Generating fallback synthetic DEM..."
        # Fallback: Generate a valid GeoTIFF using Python if download fails
        # This ensures the task is playable even if the external link breaks
        python3 -c "
import numpy as np
from osgeo import gdal, osr

driver = gdal.GetDriverByName('GTiff')
ds = driver.Create('$INPUT_FILE', 100, 100, 1, gdal.GDT_Float32)
srs = osr.SpatialReference()
srs.ImportFromEPSG(4326)
ds.SetProjection(srs.ExportToWkt())
ds.SetGeoTransform([19.0, 0.01, 0, -34.0, 0, -0.01])
band = ds.GetRasterBand(1)
# Create a gradient from 800 to 1600
data = np.linspace(800, 1600, 100).reshape(1, 100) + np.linspace(0, 200, 100).reshape(100, 1)
band.WriteArray(data)
band.FlushCache()
ds = None
"
    fi
fi

# Set permissions
chown -R ga:ga "/home/ga/GIS_Data"

# Record baseline state
ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l > /tmp/initial_export_count || echo "0" > /tmp/initial_export_count

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure QGIS is running
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS
sleep 5
wait_for_window "QGIS" 45
sleep 2

# Maximize
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="