#!/bin/bash
echo "=== Setting up reproject_and_measure_distances task ==="

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
if [ ! -f "/home/ga/GIS_Data/sample_lines.geojson" ]; then
    echo "ERROR: sample_lines.geojson not found!"
    exit 1
fi

# Verify source data has expected features
python3 << 'PYEOF'
import json
with open("/home/ga/GIS_Data/sample_lines.geojson") as f:
    data = json.load(f)
features = data.get("features", [])
print(f"Source line features: {len(features)}")
for feat in features:
    props = feat["properties"]
    coords = feat["geometry"]["coordinates"]
    print(f"  {props['name']} ({props['type']}): {len(coords)} vertices")
PYEOF

# Clean up any previous output
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/road_measurements.csv" 2>/dev/null || true
rm -f "$EXPORT_DIR/roads_utm.geojson" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR" 2>/dev/null || true

# Record baseline
ls -1 "$EXPORT_DIR"/*.csv 2>/dev/null | wc -l > /tmp/initial_csv_count || echo "0" > /tmp/initial_csv_count
ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l > /tmp/initial_geojson_count || echo "0" > /tmp/initial_geojson_count
echo "Initial CSV count: $(cat /tmp/initial_csv_count)"
echo "Initial GeoJSON count: $(cat /tmp/initial_geojson_count)"

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
