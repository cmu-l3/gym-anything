#!/bin/bash
echo "=== Setting up Terrain Analysis Task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Directories
DATA_DIR="/home/ga/GIS_Data/rasters"
EXPORT_DIR="/home/ga/GIS_Data/exports"
PROJECT_DIR="/home/ga/GIS_Data/projects"

mkdir -p "$DATA_DIR" "$EXPORT_DIR" "$PROJECT_DIR"

# Clean up previous outputs to ensure fresh generation
rm -f "$EXPORT_DIR/hillshade.tif"
rm -f "$EXPORT_DIR/slope.tif"
rm -f "$PROJECT_DIR/terrain_analysis.qgz"
rm -f "$PROJECT_DIR/terrain_analysis.qgs"

# 2. Generate/Download "Real" DEM Data
# Since external downloads can be flaky, we generate a realistic synthetic terrain 
# (simulating a hill/mountain structure) using Python and GDAL.
# This ensures the task is self-contained and reproducible while providing non-trivial data.

DEM_PATH="$DATA_DIR/bay_area_dem.tif"

echo "Generating realistic DEM data..."
python3 << 'PYEOF'
import numpy as np
from osgeo import gdal, osr

def generate_terrain(width, height):
    # Create a grid
    x = np.linspace(-3, 3, width)
    y = np.linspace(-3, 3, height)
    X, Y = np.meshgrid(x, y)
    
    # Generate terrain using mixed Gaussians to simulate peaks and valleys
    # This avoids "perfect sine waves" and looks more like a hill structure
    z = 300 * np.exp(-(X**2 + Y**2))  # Main peak
    z += 100 * np.exp(-((X-1.5)**2 + (Y-1.5)**2))  # Secondary peak
    z -= 50 * np.exp(-((X+1)**2 + (Y+1)**2))  # Depression/Valley
    
    # Add some noise to make it realistic
    np.random.seed(42)
    noise = np.random.normal(0, 2, (height, width))
    z += noise
    
    # Ensure positive elevation
    z = z - np.min(z)
    return z

# Output settings
filename = "/home/ga/GIS_Data/rasters/bay_area_dem.tif"
width, height = 500, 500
terrain = generate_terrain(width, height)

# Create GeoTIFF
driver = gdal.GetDriverByName("GTiff")
ds = driver.Create(filename, width, height, 1, gdal.GDT_Float32)

# Set Geotransform (roughly Bay Area lat/lon)
# Top-Left X, Pixel Width, 0, Top-Left Y, 0, Pixel Height (negative)
ds.SetGeoTransform([-122.5, 0.0002, 0, 37.8, 0, -0.0002])

# Set CRS (WGS84)
srs = osr.SpatialReference()
srs.ImportFromEPSG(4326)
ds.SetProjection(srs.ExportToWkt())

# Write data
band = ds.GetRasterBand(1)
band.WriteArray(terrain)
band.SetNoDataValue(-9999)
band.ComputeStatistics(False)

ds = None
print(f"Created DEM at {filename}")
PYEOF

# Ensure permissions
chown -R ga:ga "/home/ga/GIS_Data"

# 3. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 4. Launch QGIS
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS to load
wait_for_window "QGIS" 40
sleep 5

# 5. Capture Initial State
take_screenshot /tmp/task_start.png

echo "=== Task Setup Complete ==="