#!/bin/bash
echo "=== Setting up mosaic_elevation_tiles_merge task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions for utilities
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

# 1. Prepare Data Directories
DATA_DIR="/home/ga/GIS_Data/rasters"
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$DATA_DIR"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/merged_dem.tif" 2>/dev/null || true

# 2. Generate Synthetic Raster Tiles
# We use Python/GDAL to create valid GeoTIFFs with elevation-like data
echo "Generating raster tiles..."
python3 << 'PYEOF'
import numpy as np
from osgeo import gdal, osr

def create_raster(filename, min_x, max_x, min_y, max_y, start_val, end_val):
    # Resolution
    pixel_size = 0.005 # approx 500m
    cols = int((max_x - min_x) / pixel_size)
    rows = int((max_y - min_y) / pixel_size)
    
    driver = gdal.GetDriverByName('GTiff')
    out_ds = driver.Create(filename, cols, rows, 1, gdal.GDT_Float32)
    
    # Set Geotransform [top_left_x, w_e_pixel_res, rotation_0, top_left_y, rotation_0, n_s_pixel_res]
    out_ds.SetGeoTransform([min_x, pixel_size, 0, max_y, 0, -pixel_size])
    
    # Set CRS (WGS84)
    srs = osr.SpatialReference()
    srs.ImportFromEPSG(4326)
    out_ds.SetProjection(srs.ExportToWkt())
    
    # Create gradient data
    data = np.linspace(start_val, end_val, cols)
    data = np.tile(data, (rows, 1))
    
    # Write data
    out_band = out_ds.GetRasterBand(1)
    out_band.WriteArray(data)
    out_band.SetNoDataValue(-9999)
    out_band.FlushCache()
    out_ds = None
    print(f"Created {filename}")

# Tile West: -122.5 to -122.0, 37.5 to 38.0. Values 0-500
create_raster("/home/ga/GIS_Data/rasters/dem_tile_west.tif", 
              -122.5, -122.0, 37.5, 38.0, 0, 500)

# Tile East: -122.0 to -121.5, 37.5 to 38.0. Values 500-1000
create_raster("/home/ga/GIS_Data/rasters/dem_tile_east.tif", 
              -122.0, -121.5, 37.5, 38.0, 500, 1000)
PYEOF

# Fix permissions
chown -R ga:ga "/home/ga/GIS_Data"

# 3. Launch QGIS
# Kill any existing instances first
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
# Launching with no project loaded
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# 4. Wait for Window and Initialize
sleep 5
wait_for_window "QGIS" 45
sleep 3

# Maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "QGIS" | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
fi

# 5. Record Initial State
date +%s > /tmp/task_start_timestamp
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="