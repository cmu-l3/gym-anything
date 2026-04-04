#!/bin/bash
echo "=== Setting up spatial_join_points_to_polygons task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
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
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi

# Verify source data exists
if [ ! -f "/home/ga/GIS_Data/sample_polygon.geojson" ]; then
    echo "ERROR: sample_polygon.geojson not found!"
    exit 1
fi
if [ ! -f "/home/ga/GIS_Data/sample_points.geojson" ]; then
    echo "ERROR: sample_points.geojson not found!"
    exit 1
fi

# Verify data integrity: all 3 points should fall within polygons
python3 << 'PYEOF'
import json

with open("/home/ga/GIS_Data/sample_points.geojson") as f:
    points = json.load(f)
with open("/home/ga/GIS_Data/sample_polygon.geojson") as f:
    polys = json.load(f)

print(f"Points: {len(points['features'])} features")
print(f"Polygons: {len(polys['features'])} features")

for pt in points["features"]:
    c = pt["geometry"]["coordinates"]
    name = pt["properties"]["name"]
    print(f"  {name}: [{c[0]}, {c[1]}]")

for poly in polys["features"]:
    name = poly["properties"]["name"]
    coords = poly["geometry"]["coordinates"][0]
    xs = [c[0] for c in coords]
    ys = [c[1] for c in coords]
    print(f"  {name}: x=[{min(xs)},{max(xs)}] y=[{min(ys)},{max(ys)}]")
PYEOF

# Clean up any previous output
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/points_with_polygon_info.geojson" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR" 2>/dev/null || true

# Record baseline state
ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l > /tmp/initial_export_count || echo "0" > /tmp/initial_export_count
echo "Initial export count: $(cat /tmp/initial_export_count)"

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Kill any running QGIS
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

sleep 5
wait_for_window "QGIS" 30
sleep 3

take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
