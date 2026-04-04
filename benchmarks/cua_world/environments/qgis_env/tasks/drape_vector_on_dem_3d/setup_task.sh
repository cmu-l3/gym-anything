#!/bin/bash
set -e
echo "=== Setting up Drape Vector on DEM Task ==="

source /workspace/scripts/task_utils.sh

DATA_DIR="/home/ga/GIS_Data"
EXPORT_DIR="$DATA_DIR/exports"
mkdir -p "$EXPORT_DIR"
mkdir -p "$DATA_DIR/rasters"
chown -R ga:ga "$DATA_DIR"

# 1. Download Real SRTM Data (Western Cape, South Africa)
SRTM_URL="https://github.com/qgis/QGIS-Training-Data/raw/master/exercise_data/raster/SRTM/srtm_41_19.tif"
SRTM_PATH="$DATA_DIR/srtm_41_19.tif"

if [ ! -f "$SRTM_PATH" ]; then
    echo "Downloading SRTM data..."
    # Try wget with retries
    wget -q --tries=3 --timeout=20 -O "$SRTM_PATH" "$SRTM_URL" || {
        echo "Primary download failed, generating synthetic fallback..."
        # Fallback: Create a simple synthetic GeoTIFF using Python/GDAL
        cat << 'PYEOF' | python3
import numpy as np
from osgeo import gdal, osr

# Create synthetic terrain (Gaussian hill)
width, height = 100, 100
data = np.zeros((height, width), dtype=np.float32)
y, x = np.ogrid[-2:2:100j, -2:2:100j]
data = 500 * np.exp(-(x**2 + y**2)) + 100 # Gaussian hill 600m peak

driver = gdal.GetDriverByName('GTiff')
ds = driver.Create('/home/ga/GIS_Data/srtm_41_19.tif', width, height, 1, gdal.GDT_Float32)
# Set geotransform (roughly South Africa)
ds.SetGeoTransform([19.0, 0.001, 0, -34.0, 0, -0.001])
srs = osr.SpatialReference()
srs.ImportFromEPSG(4326)
ds.SetProjection(srs.ExportToWkt())
ds.GetRasterBand(1).WriteArray(data)
ds.GetRasterBand(1).SetNoDataValue(-9999)
ds = None
PYEOF
    }
fi

# 2. Generate the 2D Trail GeoJSON (Python)
echo "Generating 2D Trail vector..."
cat << 'PYEOF' | python3
import json
import os

# Define a path that crosses the DEM area (approx 19.0 to 19.1 lon, -34.0 to -34.1 lat)
trail_geojson = {
    "type": "FeatureCollection",
    "name": "proposed_trail_2d",
    "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
    "features": [
        {
            "type": "Feature",
            "properties": { "id": 1, "name": "Cape Loop Trail", "difficulty": "Moderate" },
            "geometry": {
                "type": "LineString",
                "coordinates": [
                    [19.02, -34.02],
                    [19.03, -34.03],
                    [19.04, -34.035],
                    [19.05, -34.04],
                    [19.06, -34.03],
                    [19.07, -34.025]
                ]
            }
        }
    ]
}

with open('/home/ga/GIS_Data/proposed_trail_2d.geojson', 'w') as f:
    json.dump(trail_geojson, f)
PYEOF

# Ensure permissions
chown ga:ga "$SRTM_PATH"
chown ga:ga "$DATA_DIR/proposed_trail_2d.geojson"

# Clean up any previous outputs
rm -f "$EXPORT_DIR/trail_3d.gpkg" 2>/dev/null || true
rm -f "$EXPORT_DIR/trail_3d.geojson" 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time.txt

# 3. Launch QGIS
# Kill any existing instances first
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS to be ready
wait_for_window "QGIS" 40
sleep 5

# Maximize window
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="