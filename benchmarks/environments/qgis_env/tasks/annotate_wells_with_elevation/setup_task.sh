#!/bin/bash
echo "=== Setting up annotate_wells_with_elevation task ==="

source /workspace/scripts/task_utils.sh

# Directory setup
RASTER_DIR="/home/ga/GIS_Data/rasters"
VECTOR_DIR="/home/ga/GIS_Data/vectors"
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$RASTER_DIR" "$VECTOR_DIR" "$EXPORT_DIR"

# 1. Prepare Raster Data (SRTM)
RASTER_FILE="$RASTER_DIR/SRTM_Elevation.tif"
if [ ! -f "$RASTER_FILE" ]; then
    echo "Downloading SRTM sample data..."
    # Use standard QGIS sample data URL
    wget -q -O "$RASTER_FILE" "https://github.com/qgis/QGIS-Sample-Data/raw/master/qgis_sample_data/raster/SRTM_05_44.tif" || \
    {
        echo "Download failed, generating synthetic DEM..."
        # Fallback: Generate a gradient GeoTIFF if download fails (to ensure task is playable)
        python3 -c "
import numpy as np
from osgeo import gdal, osr
driver = gdal.GetDriverByName('GTiff')
ds = driver.Create('$RASTER_FILE', 100, 100, 1, gdal.GDT_Float32)
srs = osr.SpatialReference()
srs.ImportFromEPSG(4326)
ds.SetProjection(srs.ExportToWkt())
ds.SetGeoTransform([-122.5, 0.01, 0, 37.5, 0, -0.01])
band = ds.GetRasterBand(1)
data = np.fromfunction(lambda y, x: x + y, (100, 100))
band.WriteArray(data)
band.SetNoDataValue(-9999)
ds = None
"
    }
fi
chown ga:ga "$RASTER_FILE"

# 2. Prepare Vector Data (Monitoring Wells)
VECTOR_FILE="$VECTOR_DIR/monitoring_wells.geojson"
echo "Generating monitoring wells..."
python3 -c "
import json
import random
from osgeo import gdal

# Open raster to get bounds
ds = gdal.Open('$RASTER_FILE')
gt = ds.GetGeoTransform()
width = ds.RasterXSize
height = ds.RasterYSize
minx = gt[0]
maxx = minx + (width * gt[1])
maxy = gt[3]
miny = maxy + (height * gt[5])

# Generate random points within bounds (inset slightly to avoid edges)
points = []
for i in range(15):
    x = random.uniform(minx + 0.05, maxx - 0.05)
    y = random.uniform(miny + 0.05, maxy - 0.05)
    points.append({
        'type': 'Feature',
        'properties': {'id': i+1, 'well_name': f'MW-{i+1:03d}'},
        'geometry': {
            'type': 'Point',
            'coordinates': [x, y]
        }
    })

geojson = {
    'type': 'FeatureCollection',
    'name': 'monitoring_wells',
    'crs': { 'type': 'name', 'properties': { 'name': 'urn:ogc:def:crs:OGC:1.3:CRS84' } },
    'features': points
}

with open('$VECTOR_FILE', 'w') as f:
    json.dump(geojson, f)
"
chown ga:ga "$VECTOR_FILE"

# Clean previous exports
rm -f "$EXPORT_DIR/wells_with_elevation.geojson"

# 3. Launch QGIS with layers
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS with data..."
# QGIS can load layers passed as arguments
su - ga -c "DISPLAY=:1 qgis '$RASTER_FILE' '$VECTOR_FILE' > /tmp/qgis_task.log 2>&1 &"

# Wait for window
wait_for_window "QGIS" 60
sleep 5

# Maximize
wid=$(get_qgis_window_id)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Record start time
date +%s > /tmp/task_start_time

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="