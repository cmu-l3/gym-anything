#!/bin/bash
echo "=== Setting up Viewshed Fire Lookout Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi

# Ensure raster directory exists
RASTER_DIR="/home/ga/GIS_Data/rasters"
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$RASTER_DIR"
mkdir -p "$EXPORT_DIR"

# Clean up previous task artifacts
rm -f "$EXPORT_DIR/fire_lookout_viewshed.tif" 2>/dev/null || true
rm -f "$RASTER_DIR/dem_reprojected.tif" 2>/dev/null || true

# Prepare input data (Real SRTM tile)
DEM_FILE="$RASTER_DIR/srtm_41_19.tif"

if [ ! -f "$DEM_FILE" ]; then
    echo "Downloading DEM data..."
    # Using a reliable source for a small clipped DEM of Western Cape (Swellendam area)
    # If direct download fails, we create a fallback "real" data simulation using Python noise
    # to ensure the task is runnable, but we prefer the real download.
    
    # Try download specific tile subset
    wget -q -O "$DEM_FILE" "https://github.com/qgis/QGIS-Training-Data/raw/master/exercise_data/raster/SRTM/srtm_41_19.tif" || \
    wget -q -O "$DEM_FILE" "https://raw.githubusercontent.com/qgis/QGIS-Training-Data/master/exercise_data/raster/SRTM/srtm_41_19.tif"
    
    # Verify download
    if [ ! -s "$DEM_FILE" ]; then
        echo "Download failed. Generating synthetic terrain for fallback (Not ideal but necessary for offline robustness)..."
        python3 -c "
import numpy as np
from osgeo import gdal, osr

width, height = 1000, 1000
driver = gdal.GetDriverByName('GTiff')
ds = driver.Create('$DEM_FILE', width, height, 1, gdal.GDT_Int16)

# Set Geotransform (South Africa approximate)
ds.SetGeoTransform([20.0, 0.000833, 0, -33.0, 0, -0.000833])

# Set SRS (WGS84)
srs = osr.SpatialReference()
srs.ImportFromEPSG(4326)
ds.SetProjection(srs.ExportToWkt())

# Generate a mountain peak
x = np.linspace(-5, 5, width)
y = np.linspace(-5, 5, height)
X, Y = np.meshgrid(x, y)
R = np.sqrt(X**2 + Y**2)
Z = np.sin(R) * 500 + 1000 - (R*100)
Z = Z.astype(np.int16)
Z[Z < 0] = 0

ds.GetRasterBand(1).WriteArray(Z)
ds.FlushCache()
"
    fi
fi

# Set permissions
chown -R ga:ga "$RASTER_DIR" "$EXPORT_DIR"

# Record task start time
date +%s > /tmp/task_start_timestamp

# Record initial state
ls -1 "$EXPORT_DIR"/*.tif 2>/dev/null | wc -l > /tmp/initial_export_count || echo "0" > /tmp/initial_export_count

# Kill any running QGIS
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

sleep 5
wait_for_window "QGIS" 45
sleep 3

# Maximize
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Input data: $DEM_FILE"