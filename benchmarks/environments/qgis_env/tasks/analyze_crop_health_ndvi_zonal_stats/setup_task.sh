#!/bin/bash
echo "=== Setting up analyze_crop_health_ndvi_zonal_stats task ==="

source /workspace/scripts/task_utils.sh

# Define paths
DATA_DIR="/home/ga/GIS_Data/agriculture"
EXPORT_DIR="/home/ga/GIS_Data/exports"

# Create directories
mkdir -p "$DATA_DIR"
mkdir -p "$EXPORT_DIR"

# Clean up previous run artifacts
rm -f "$DATA_DIR/farm_imagery.tif"
rm -f "$DATA_DIR/field_boundaries.geojson"
rm -f "$DATA_DIR/ndvi_output.tif"
rm -f "$EXPORT_DIR/fields_with_yield_potential.geojson"

# ------------------------------------------------------------------
# Generate Synthetic Data using Python (GDAL/NumPy)
# ------------------------------------------------------------------
echo "Generating synthetic multispectral data..."

python3 << 'PYEOF'
import numpy as np
from osgeo import gdal, osr
import json
import os

# Define output paths
raster_path = "/home/ga/GIS_Data/agriculture/farm_imagery.tif"
vector_path = "/home/ga/GIS_Data/agriculture/field_boundaries.geojson"

# Raster parameters
width, height = 100, 100
bands = 2
driver = gdal.GetDriverByName('GTiff')
ds = driver.Create(raster_path, width, height, bands, gdal.GDT_Float32)

# Set Geotransform (TopLeftX, PixelW, RotX, TopLeftY, RotY, PixelH)
# Arbitrary local coordinates
geotransform = [0, 10, 0, 1000, 0, -10]
ds.SetGeoTransform(geotransform)

# Set Projection (WGS84 UTM Zone 33N - EPSG:32633 for example)
srs = osr.SpatialReference()
srs.ImportFromEPSG(32633)
ds.SetProjection(srs.ExportToWkt())

# Create data arrays
# Band 1: Red, Band 2: NIR
red_band = np.zeros((height, width), dtype=np.float32)
nir_band = np.zeros((height, width), dtype=np.float32)

# Define Zones (Simple rectangular fields for robustness)
# Field A (Top Left): Healthy Vegetation (Low Red, High NIR) -> High NDVI
# y: 0-50, x: 0-50
red_band[0:50, 0:50] = 0.1
nir_band[0:50, 0:50] = 0.8

# Field B (Top Right): Stressed Vegetation (Med Red, Med NIR) -> Med NDVI
# y: 0-50, x: 50-100
red_band[0:50, 50:100] = 0.3
nir_band[0:50, 50:100] = 0.5

# Field C (Bottom): Soil/Fallow (High Red, Low NIR) -> Low/Neg NDVI
# y: 50:100, x: 0-100
red_band[50:100, :] = 0.6
nir_band[50:100, :] = 0.2

# Add some noise to make it realistic
np.random.seed(42)
red_band += np.random.normal(0, 0.02, red_band.shape)
nir_band += np.random.normal(0, 0.02, nir_band.shape)

# Clip to valid range 0-1
red_band = np.clip(red_band, 0.0, 1.0)
nir_band = np.clip(nir_band, 0.0, 1.0)

# Write bands
ds.GetRasterBand(1).WriteArray(red_band) # Red
ds.GetRasterBand(2).WriteArray(nir_band) # NIR
ds.FlushCache()
ds = None

print(f"Created raster: {raster_path}")

# Create corresponding Vector Data (GeoJSON)
# Coordinates must match the raster geotransform
# 0,0 is top-left.
# Field A: (0, 1000) to (500, 500)
# Field B: (500, 1000) to (1000, 500)
# Field C: (0, 500) to (1000, 0)

geojson = {
  "type": "FeatureCollection",
  "name": "field_boundaries",
  "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:EPSG::32633" } },
  "features": [
    {
      "type": "Feature",
      "properties": { "id": 1, "name": "Field_A", "crop": "Corn" },
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[0, 1000], [500, 1000], [500, 500], [0, 500], [0, 1000]]]
      }
    },
    {
      "type": "Feature",
      "properties": { "id": 2, "name": "Field_B", "crop": "Wheat" },
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[500, 1000], [1000, 1000], [1000, 500], [500, 500], [500, 1000]]]
      }
    },
    {
      "type": "Feature",
      "properties": { "id": 3, "name": "Field_C", "crop": "Fallow" },
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[0, 500], [1000, 500], [1000, 0], [0, 0], [0, 500]]]
      }
    }
  ]
}

with open(vector_path, 'w') as f:
    json.dump(geojson, f)

print(f"Created vector: {vector_path}")
PYEOF

# Fix permissions
chown -R ga:ga "$DATA_DIR"
chown -R ga:ga "$EXPORT_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start QGIS
kill_qgis ga 2>/dev/null || true
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for window
wait_for_window "QGIS" 45
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="