#!/bin/bash
echo "=== Setting up Solar Suitability Analysis Task ==="

source /workspace/scripts/task_utils.sh

# 1. Create directories
mkdir -p /home/ga/GIS_Data/exports
mkdir -p /home/ga/GIS_Data/rasters

# 2. Prepare Input Data (DEM)
DEM_PATH="/home/ga/GIS_Data/elevation.tif"

# We will generate a synthetic DEM using Python to ensure consistency and avoid external download dependencies during runtime
# This creates a "hill" in the middle to provide varied slope and aspect
echo "Generating synthetic DEM data..."
python3 -c '
import numpy as np
from osgeo import gdal, osr

# Parameters
width, height = 500, 500
filename = "/home/ga/GIS_Data/elevation.tif"

# Create elevation data: A Gaussian hill + some noise
x = np.linspace(-1000, 1000, width)
y = np.linspace(-1000, 1000, height)
X, Y = np.meshgrid(x, y)
# Gaussian hill centered at 0,0
Z = 200 * np.exp(-(X**2 + Y**2) / (500**2)) 
# Add a tilted plane to ensure we have south-facing slopes
Z += (Y * 0.05) 
# Ensure positive elevation
Z += 100 

# Create GeoTIFF
driver = gdal.GetDriverByName("GTiff")
ds = driver.Create(filename, width, height, 1, gdal.GDT_Float32)

# Set CRS (Projected: UTM Zone 10N - EPSG:32610)
srs = osr.SpatialReference()
srs.ImportFromEPSG(32610)
ds.SetProjection(srs.ExportToWkt())

# Set GeoTransform (TopLeftX, PixelW, RotX, TopLeftY, RotY, PixelH)
# 10m resolution
ds.SetGeoTransform([500000, 10, 0, 4200000, 0, -10])

# Write data
band = ds.GetRasterBand(1)
band.WriteArray(Z)
band.SetNoDataValue(-9999)
band.FlushCache()
ds = None
print(f"Created DEM at {filename}")
'

# Set permissions
chown ga:ga "$DEM_PATH"
chmod 644 "$DEM_PATH"
chown -R ga:ga /home/ga/GIS_Data/exports

# 3. Clean up previous results
rm -f /home/ga/GIS_Data/exports/solar_candidates.tif

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Launch QGIS
# Kill any existing QGIS
kill_qgis ga 2>/dev/null || true

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS to start
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

echo "=== Setup complete ==="