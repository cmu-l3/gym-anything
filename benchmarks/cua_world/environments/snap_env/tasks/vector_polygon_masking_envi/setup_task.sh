#!/bin/bash
echo "=== Setting up vector_polygon_masking_envi task ==="

# Clean up any existing state
rm -rf /home/ga/snap_projects/* 2>/dev/null || true
rm -rf /home/ga/snap_exports/* 2>/dev/null || true
mkdir -p /home/ga/snap_projects /home/ga/snap_exports

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_ts

# Install GDAL tools if missing (required for generating the shapefile dynamically)
if ! command -v gdalinfo &> /dev/null; then
    echo "Installing GDAL tools..."
    apt-get update -qq && apt-get install -y gdal-bin python3-gdal > /dev/null 2>&1
fi

DATA_DIR="/home/ga/snap_data"
mkdir -p "$DATA_DIR"
TIF_FILE="$DATA_DIR/landsat_multispectral.tif"
SHP_FILE="$DATA_DIR/reserve_boundary.shp"

# Ensure Landsat data exists
if [ ! -f "$TIF_FILE" ]; then
    echo "Downloading Landsat image..."
    wget -q --timeout=60 --tries=3 \
        "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
        -O "$TIF_FILE"
fi

echo "Generating ESRI Shapefile matching the image..."
# Extract spatial metadata from the GeoTIFF
gdalinfo -json "$TIF_FILE" > /tmp/info.json

# Use Python to calculate a diamond polygon occupying exactly 32% of the image
python3 << 'PYEOF'
import json
with open('/tmp/info.json') as f:
    d = json.load(f)

ul = d['cornerCoordinates']['upperLeft']
lr = d['cornerCoordinates']['lowerRight']

minx, maxx = min(ul[0], lr[0]), max(ul[0], lr[0])
miny, maxy = min(ul[1], lr[1]), max(ul[1], lr[1])

width = maxx - minx
height = maxy - miny

cx = minx + width / 2.0
cy = miny + height / 2.0

# Diamond covering 80% of width and 80% of height (Area = 0.5 * 0.8 * 0.8 = 32% of bbox)
dx = width * 0.4
dy = height * 0.4

# Construct WKT string
wkt = f"POLYGON (({cx} {cy+dy}, {cx+dx} {cy}, {cx} {cy-dy}, {cx-dx} {cy}, {cx} {cy+dy}))"

with open('/tmp/reserve.csv', 'w') as f:
    f.write("id,WKT\n")
    f.write(f'1,"{wkt}"\n')

# Extract Coordinate Reference System (CRS)
crs_wkt = d['coordinateSystem']['wkt']
with open('/tmp/crs.prj', 'w') as f:
    f.write(crs_wkt)
PYEOF

# Convert the WKT CSV to an actual ESRI Shapefile using ogr2ogr
ogr2ogr -f "ESRI Shapefile" "$SHP_FILE" /tmp/reserve.csv -dialect sqlite -sql "SELECT id, GeomFromText(WKT) as geometry FROM reserve"
cp /tmp/crs.prj "${SHP_FILE%.*}.prj"

# Fix ownership
chown -R ga:ga "$DATA_DIR"
chown -R ga:ga /home/ga/snap_projects /home/ga/snap_exports

# Launch SNAP Desktop cleanly
echo "Starting ESA SNAP Desktop..."
pkill -f "java.*snap" 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap.log 2>&1 &"

# Wait for the SNAP window to become available
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        break
    fi
    sleep 2
done
sleep 5 # Give it a few extra seconds to initialize the UI

# Dismiss any startup dialogs gracefully
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "SNAP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SNAP" 2>/dev/null || true

# Capture the starting state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="