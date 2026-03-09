#!/bin/bash
echo "=== Setting up land_use_change_union_overlay task ==="

source /workspace/scripts/task_utils.sh

# Fallback for utils if not sourced correctly
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi

# 1. Clean up previous run data
DATA_DIR="/home/ga/GIS_Data"
EXPORT_DIR="$DATA_DIR/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$DATA_DIR/landuse_2015.geojson"
rm -f "$DATA_DIR/landuse_2025.geojson"
rm -f "$EXPORT_DIR/change_matrix.csv"

# 2. Generate Synthetic Data (GeoJSONs in EPSG:32610 UTM Zone 10N)
# Using Python to ensure valid GeoJSON structure and coordinates
python3 << 'PYEOF'
import json
import os

data_dir = "/home/ga/GIS_Data"

# CRS Definition (UTM Zone 10N)
crs = { "type": "name", "properties": { "name": "urn:ogc:def:crs:EPSG::32610" } }

# 2015 Data: Forest (West), Farm (East)
# Total Area 10x10km. Split at x=5000
features_2015 = [
    {
        "type": "Feature",
        "properties": { "id": 1, "class_2015": "Forest" },
        "geometry": {
            "type": "Polygon",
            "coordinates": [[[0, 0], [0, 10000], [5000, 10000], [5000, 0], [0, 0]]]
        }
    },
    {
        "type": "Feature",
        "properties": { "id": 2, "class_2015": "Farm" },
        "geometry": {
            "type": "Polygon",
            "coordinates": [[[5000, 0], [5000, 10000], [10000, 10000], [10000, 0], [5000, 0]]]
        }
    }
]

geojson_2015 = {
    "type": "FeatureCollection",
    "name": "landuse_2015",
    "crs": crs,
    "features": features_2015
}

with open(os.path.join(data_dir, "landuse_2015.geojson"), "w") as f:
    json.dump(geojson_2015, f)

# 2025 Data: Forest (NW), Urban (SW), Farm (East)
features_2025 = [
    {
        "type": "Feature",
        "properties": { "id": 1, "class_2025": "Forest" },
        "geometry": {
            "type": "Polygon",
            "coordinates": [[[0, 5000], [0, 10000], [5000, 10000], [5000, 5000], [0, 5000]]]
        }
    },
    {
        "type": "Feature",
        "properties": { "id": 2, "class_2025": "Urban" },
        "geometry": {
            "type": "Polygon",
            "coordinates": [[[0, 0], [0, 5000], [5000, 5000], [5000, 0], [0, 0]]]
        }
    },
    {
        "type": "Feature",
        "properties": { "id": 3, "class_2025": "Farm" },
        "geometry": {
            "type": "Polygon",
            "coordinates": [[[5000, 0], [5000, 10000], [10000, 10000], [10000, 0], [5000, 0]]]
        }
    }
]

geojson_2025 = {
    "type": "FeatureCollection",
    "name": "landuse_2025",
    "crs": crs,
    "features": features_2025
}

with open(os.path.join(data_dir, "landuse_2025.geojson"), "w") as f:
    json.dump(geojson_2025, f)

PYEOF

# Set permissions
chown ga:ga "$DATA_DIR/landuse_2015.geojson"
chown ga:ga "$DATA_DIR/landuse_2025.geojson"

# 3. Task State Recording
# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
# Record initial CSV count (should be 0 after cleanup)
ls -1 "$EXPORT_DIR"/*.csv 2>/dev/null | wc -l > /tmp/initial_csv_count

# 4. Prepare Application State
# Kill any running QGIS to ensure clean slate
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS for the user
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS to appear
sleep 5
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "QGIS"; then
        echo "QGIS window found"
        break
    fi
    sleep 1
done

# Maximize QGIS
sleep 2
DISPLAY=:1 wmctrl -r "QGIS" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Setup Complete ==="