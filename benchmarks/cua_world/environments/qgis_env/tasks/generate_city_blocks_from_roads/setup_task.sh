#!/bin/bash
echo "=== Setting up generate_city_blocks_from_roads task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
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

# Create synthetic road network data (Grid of 2 blocks + 1 dangle)
# CRS: WGS84 (EPSG:4326)
# Origin near San Francisco: -122.404, 37.700
# Block size approx: 0.002 deg x 0.002 deg
python3 << 'PYEOF'
import json
import os

# Coordinates
x0, x1, x2 = -122.404, -122.402, -122.400
y0, y1 = 37.700, 37.702
x_dangle = -122.398
y_mid = 37.701

features = [
    # Vertical lines
    {"type": "Feature", "properties": {"id": 1, "type": "road"}, "geometry": {"type": "LineString", "coordinates": [[x0, y0], [x0, y1]]}},
    {"type": "Feature", "properties": {"id": 2, "type": "road"}, "geometry": {"type": "LineString", "coordinates": [[x1, y0], [x1, y1]]}},
    {"type": "Feature", "properties": {"id": 3, "type": "road"}, "geometry": {"type": "LineString", "coordinates": [[x2, y0], [x2, y1]]}},
    # Horizontal lines (split segments to ensure clean topology for simple visual inspection, 
    # though Lines to Polygons handles intersections)
    {"type": "Feature", "properties": {"id": 4, "type": "road"}, "geometry": {"type": "LineString", "coordinates": [[x0, y0], [x2, y0]]}},
    {"type": "Feature", "properties": {"id": 5, "type": "road"}, "geometry": {"type": "LineString", "coordinates": [[x0, y1], [x2, y1]]}},
    # Dangle (Dead end)
    {"type": "Feature", "properties": {"id": 6, "type": "road"}, "geometry": {"type": "LineString", "coordinates": [[x2, y_mid], [x_dangle, y_mid]]}}
]

geojson = {
    "type": "FeatureCollection",
    "name": "urban_roads",
    "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
    "features": features
}

os.makedirs("/home/ga/GIS_Data", exist_ok=True)
with open("/home/ga/GIS_Data/urban_roads.geojson", "w") as f:
    json.dump(geojson, f)

print("Created /home/ga/GIS_Data/urban_roads.geojson")
PYEOF

chown ga:ga /home/ga/GIS_Data/urban_roads.geojson

# Clean up exports
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/city_blocks.geojson" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"

# Record baseline state
echo "0" > /tmp/initial_export_count
ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l > /tmp/initial_export_count || echo "0" > /tmp/initial_export_count

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure QGIS is fresh
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

sleep 5
wait_for_window "QGIS" 30
sleep 3

# Maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "QGIS" | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
fi

take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="