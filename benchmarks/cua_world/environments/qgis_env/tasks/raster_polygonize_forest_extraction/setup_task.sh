#!/bin/bash
echo "=== Setting up raster_polygonize_forest_extraction task ==="

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

DATA_DIR="/home/ga/GIS_Data"
mkdir -p "$DATA_DIR"
chown ga:ga "$DATA_DIR"

# Generate the classified raster using Python
# We create a 100x100 raster with specific geometric shapes to act as ground truth
echo "Generating input raster..."
python3 << 'PYEOF'
import numpy as np
from osgeo import gdal, osr
import os

output_path = "/home/ga/GIS_Data/landcover_classification.tif"
width = 100
height = 100

# Create generic projected CRS (WGS 84 / UTM zone 10N)
srs = osr.SpatialReference()
srs.ImportFromEPSG(32610)

# Create raster
driver = gdal.GetDriverByName("GTiff")
ds = driver.Create(output_path, width, height, 1, gdal.GDT_Byte)

# Set geotransform (top left x, w-e pixel resolution, rotation, top left y, rotation, n-s pixel resolution)
# 100m resolution
ds.SetGeoTransform([500000, 100, 0, 4200000, 0, -100])
ds.SetProjection(srs.ExportToWkt())

# Create data array
# Initialize with 2 (Water)
data = np.full((height, width), 2, dtype=np.uint8)

# Add 3 (Urban) in the center
data[40:60, 40:60] = 3

# Add 1 (Forest) in 4 distinct corners to ensure 4 distinct polygons
# Top-Left
data[10:30, 10:30] = 1
# Top-Right
data[10:30, 70:90] = 1
# Bottom-Left
data[70:90, 10:30] = 1
# Bottom-Right
data[70:90, 70:90] = 1

# Write data
band = ds.GetRasterBand(1)
band.WriteArray(data)
band.SetNoDataValue(0)
band.FlushCache()

ds = None
print(f"Created raster at {output_path}")
PYEOF

chown ga:ga "/home/ga/GIS_Data/landcover_classification.tif"

# Clean output directory
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/forest_zones.geojson" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"

# Record baseline state
echo "0" > /tmp/initial_export_count
ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l > /tmp/initial_export_count || echo "0" > /tmp/initial_export_count

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Kill any running QGIS
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

sleep 5
wait_for_window "QGIS" 30
sleep 3

take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="