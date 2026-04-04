#!/bin/bash
echo "=== Setting up land_cover_stats_calculation task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions for utilities if not present
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

# 1. Create Directories
mkdir -p /home/ga/GIS_Data/rasters
mkdir -p /home/ga/GIS_Data/exports
chown -R ga:ga /home/ga/GIS_Data

# 2. Generate Vector Data (Management Zones)
# Two polygons: Area A (West), Area B (East)
# Extent: -122.5 to -121.9, 37.5 to 37.8
cat > /home/ga/GIS_Data/sample_polygon.geojson << 'EOF'
{
  "type": "FeatureCollection",
  "name": "sample_polygon",
  "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
  "features": [
    {
      "type": "Feature",
      "properties": { "id": 1, "name": "Area A" },
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[-122.5, 37.5], [-122.5, 37.8], [-122.2, 37.8], [-122.2, 37.5], [-122.5, 37.5]]]
      }
    },
    {
      "type": "Feature",
      "properties": { "id": 2, "name": "Area B" },
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[-122.2, 37.5], [-122.2, 37.8], [-121.9, 37.8], [-121.9, 37.5], [-122.2, 37.5]]]
      }
    }
  ]
}
EOF

# 3. Generate Raster Data (Land Cover) programmatically using Python/GDAL
# We create a 600x300 pixel raster to cover the area.
# West half (cols 0-300) = 1 (Water)
# East half (cols 300-600) = 2 (Forest)
# Add some noise (Class 3) so math isn't too trivial.

python3 << 'PYEOF'
import numpy as np
from osgeo import gdal, osr

output_path = "/home/ga/GIS_Data/rasters/landcover.tif"
width, height = 600, 300
min_x, max_y = -122.5, 37.8
max_x, min_y = -121.9, 37.5
pixel_width = (max_x - min_x) / width
pixel_height = (min_y - max_y) / height  # Negative value

# Create driver
driver = gdal.GetDriverByName('GTiff')
dataset = driver.Create(output_path, width, height, 1, gdal.GDT_Byte)

# Set Geotransform
dataset.SetGeoTransform((min_x, pixel_width, 0, max_y, 0, pixel_height))

# Set Projection (WGS84)
srs = osr.SpatialReference()
srs.ImportFromEPSG(4326)
dataset.SetProjection(srs.ExportToWkt())

# Generate Data
data = np.zeros((height, width), dtype=np.uint8)

# Area A (West) roughly cols 0-300 -> Class 1 (Water)
data[:, :300] = 1

# Area B (East) roughly cols 300-600 -> Class 2 (Forest)
data[:, 300:] = 2

# Add random noise (Class 3 Urban) - 1% of pixels
noise = np.random.rand(height, width)
data[noise > 0.99] = 3

# Write data
band = dataset.GetRasterBand(1)
band.WriteArray(data)
band.SetNoDataValue(0)
band.FlushCache()

# Cleanup
dataset = None
print(f"Created raster at {output_path}")
PYEOF

# Fix permissions
chown ga:ga /home/ga/GIS_Data/sample_polygon.geojson
chown ga:ga /home/ga/GIS_Data/rasters/landcover.tif

# 4. Clean previous outputs
rm -f /home/ga/GIS_Data/exports/zone_composition.geojson 2>/dev/null || true

# 5. Record Initial State
date +%s > /tmp/task_start_timestamp

# 6. Launch QGIS
kill_qgis ga 2>/dev/null || true
sleep 1
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# 7. Wait and Setup Window
sleep 5
wait_for_window "QGIS" 40
sleep 2

# Maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "QGIS" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -ia "$WID"
fi

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="