#!/bin/bash
echo "=== Setting up repair_invalid_geometry_parcels task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if utils not loaded
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

# 1. Generate the invalid data
echo "Generating data with topological errors..."
mkdir -p /home/ga/GIS_Data
cat > /home/ga/GIS_Data/prep_data.py << 'PYEOF'
import json
import os

output_path = "/home/ga/GIS_Data/parcels_with_errors.geojson"

# Create a self-intersecting polygon (hourglass/bowtie shape)
# Coordinates: (0,0) -> (0,10) -> (10,0) -> (10,10) -> (0,0)
# This crosses at (5,5)
bowtie_geom = {
    "type": "Polygon",
    "coordinates": [[[0, 0], [0, 10], [10, 0], [10, 10], [0, 0]]]
}

geojson = {
    "type": "FeatureCollection",
    "name": "parcels_with_errors",
    "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
    "features": [
        {
            "type": "Feature",
            "properties": { "id": 1, "owner": "Smith", "type": "Residential" },
            "geometry": { "type": "Polygon", "coordinates": [[[-5, 0], [-5, 10], [-2, 10], [-2, 0], [-5, 0]]] }
        },
        {
            "type": "Feature",
            "properties": { "id": 2, "owner": "Doe", "type": "Commercial" },
            "geometry": bowtie_geom
        },
        {
            "type": "Feature",
            "properties": { "id": 3, "owner": "City", "type": "Park" },
            "geometry": { "type": "Polygon", "coordinates": [[[12, 0], [15, 10], [18, 0], [12, 0]]] }
        }
    ]
}

with open(output_path, 'w') as f:
    json.dump(geojson, f)

print(f"Created {output_path}")
PYEOF

python3 /home/ga/GIS_Data/prep_data.py
chown ga:ga /home/ga/GIS_Data/parcels_with_errors.geojson

# 2. Clean output directory
mkdir -p /home/ga/GIS_Data/exports
rm -f /home/ga/GIS_Data/exports/parcels_fixed.geojson 2>/dev/null || true
chown -R ga:ga /home/ga/GIS_Data/exports

# 3. Record baseline state
date +%s > /tmp/task_start_timestamp

# 4. Ensure QGIS is running
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

sleep 5
wait_for_window "QGIS" 30
sleep 2

# Maximize
DISPLAY=:1 wmctrl -r "QGIS" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="