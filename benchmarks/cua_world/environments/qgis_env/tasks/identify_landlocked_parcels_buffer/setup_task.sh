#!/bin/bash
echo "=== Setting up identify_landlocked_parcels_buffer task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi

# Create data directories
DATA_DIR="/home/ga/GIS_Data/cadastral"
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$DATA_DIR"
mkdir -p "$EXPORT_DIR"
chown -R ga:ga "/home/ga/GIS_Data"

# Clean previous output
rm -f "$EXPORT_DIR/easement_buffers.geojson" 2>/dev/null || true

# Generate synthetic data using Python
# Grid is 3x3, 100m cells.
# Origin at a location in UTM Zone 10N, then converted to Lat/Lon for the source file.
# Origin: 500000, 4200000 (approx SF area in UTM 10N)
# P1(0,0), P2(100,0), P3(200,0) ...
# Road U-shape: Left(x=0), Bottom(y=0), Right(x=300)

echo "Generating synthetic cadastral data..."
python3 << 'PYEOF'
import json
import os
try:
    from pyproj import Transformer
    from shapely.geometry import Polygon, LineString, mapping
    from shapely.ops import transform
except ImportError:
    print("Warning: shapely/pyproj not found. Creating simplified GeoJSON manually.")
    # Fallback to manual creation if libraries missing (unlikely in this env)
    exit(1)

# CRS Setup: UTM 10N to WGS84
# We create data in meters (easier logic) then project to WGS84 for the task input
transformer = Transformer.from_crs("EPSG:32610", "EPSG:4326", always_xy=True)

base_x = 550000
base_y = 4180000
cell_size = 100

features_parcels = []
features_roads = []

# Create 3x3 Grid of Parcels
# Row 0 (Bottom): y=0-100
# Row 1 (Mid):    y=100-200
# Row 2 (Top):    y=200-300
pid = 1
for r in range(3):
    for c in range(3):
        x1 = base_x + c * cell_size
        y1 = base_y + r * cell_size
        x2 = x1 + cell_size
        y2 = y1 + cell_size
        
        poly_utm = Polygon([(x1, y1), (x2, y1), (x2, y2), (x1, y2), (x1, y1)])
        
        # Project to WGS84
        poly_wgs = transform(transformer.transform, poly_utm)
        
        features_parcels.append({
            "type": "Feature",
            "properties": {"id": pid, "row": r, "col": c},
            "geometry": mapping(poly_wgs)
        })
        pid += 1

# Create Road Network (U-Shape surrounding the block)
# Left edge: x=0, y=0 to 300
# Bottom edge: y=0, x=0 to 300
# Right edge: x=300, y=0 to 300
# Top is OPEN

# Coordinates relative to base
p00 = (base_x, base_y)
p03 = (base_x, base_y + 300)
p30 = (base_x + 300, base_y)
p33 = (base_x + 300, base_y + 300)

# Single MultiLineString or LineString
road_geom_utm = LineString([p03, p00, p30, p33]) # Left -> Bottom -> Right
road_geom_wgs = transform(transformer.transform, road_geom_utm)

features_roads.append({
    "type": "Feature",
    "properties": {"name": "Main Street Loop", "type": "primary"},
    "geometry": mapping(road_geom_wgs)
})

# Save Parcels
parcels_fc = {
    "type": "FeatureCollection",
    "name": "subdivision_parcels",
    "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
    "features": features_parcels
}
with open("/home/ga/GIS_Data/cadastral/subdivision_parcels.geojson", "w") as f:
    json.dump(parcels_fc, f)

# Save Roads
roads_fc = {
    "type": "FeatureCollection",
    "name": "road_network",
    "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
    "features": features_roads
}
with open("/home/ga/GIS_Data/cadastral/road_network.geojson", "w") as f:
    json.dump(roads_fc, f)

print("Data generation complete.")
PYEOF

# Fix permissions
chown -R ga:ga "$DATA_DIR"

# Record baseline counts
ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l > /tmp/initial_export_count || echo "0" > /tmp/initial_export_count

# Timestamp
date +%s > /tmp/task_start_timestamp

# Kill QGIS if running
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

sleep 5
wait_for_window "QGIS" 45
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="