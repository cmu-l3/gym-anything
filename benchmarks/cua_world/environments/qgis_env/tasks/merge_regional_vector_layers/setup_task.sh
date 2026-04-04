#!/bin/bash
set -e
echo "=== Setting up merge_regional_vector_layers task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Directory Structure
DATA_DIR="/home/ga/GIS_Data/regions"
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$DATA_DIR"
mkdir -p "$EXPORT_DIR"

# Clean up previous runs
rm -f "$EXPORT_DIR/merged_countries.geojson" 2>/dev/null || true
rm -f "/tmp/ground_truth_counts.json" 2>/dev/null || true

# 2. Download and Prepare Data (Natural Earth 110m Countries)
# Using a stable mirror for Natural Earth data
NE_URL="https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson"
FULL_DATASET="/tmp/ne_countries_full.geojson"

if [ ! -f "$FULL_DATASET" ]; then
    echo "Downloading Natural Earth dataset..."
    wget -q -O "$FULL_DATASET" "$NE_URL" || {
        echo "Primary download failed. Creating fallback synthetic data..."
        # Fallback: Create simple synthetic data if download fails
        cat > "$FULL_DATASET" << 'EOF'
{
"type": "FeatureCollection", "features": [
{"type":"Feature","properties":{"NAME":"France","CONTINENT":"Europe"},"geometry":{"type":"Polygon","coordinates":[[[2,46],[2,48],[4,48],[4,46],[2,46]]]}},
{"type":"Feature","properties":{"NAME":"Germany","CONTINENT":"Europe"},"geometry":{"type":"Polygon","coordinates":[[[10,50],[10,52],[12,52],[12,50],[10,50]]]}},
{"type":"Feature","properties":{"NAME":"South Africa","CONTINENT":"Africa"},"geometry":{"type":"Polygon","coordinates":[[[20,-30],[20,-28],[22,-28],[22,-30],[20,-30]]]}},
{"type":"Feature","properties":{"NAME":"Egypt","CONTINENT":"Africa"},"geometry":{"type":"Polygon","coordinates":[[[30,26],[30,28],[32,28],[32,26],[30,26]]]}},
{"type":"Feature","properties":{"NAME":"Brazil","CONTINENT":"South America"},"geometry":{"type":"Polygon","coordinates":[[[-50,-10],[-50,-8],[-48,-8],[-48,-10],[-50,-10]]]}}
]}
EOF
    }
fi

# 3. Split Data by Continent using ogr2ogr (available in QGIS env)
echo "Splitting data by continent..."

# Extract Europe
ogr2ogr -f "GeoJSON" "$DATA_DIR/europe_countries.geojson" "$FULL_DATASET" \
    -where "CONTINENT = 'Europe'" 2>/dev/null

# Extract Africa
ogr2ogr -f "GeoJSON" "$DATA_DIR/africa_countries.geojson" "$FULL_DATASET" \
    -where "CONTINENT = 'Africa'" 2>/dev/null

# Extract South America
ogr2ogr -f "GeoJSON" "$DATA_DIR/south_america_countries.geojson" "$FULL_DATASET" \
    -where "CONTINENT = 'South America'" 2>/dev/null

# 4. Generate Ground Truth Counts
echo "Calculating ground truth..."
python3 << 'PYEOF'
import json
import os

data_dir = "/home/ga/GIS_Data/regions"
regions = ["europe_countries.geojson", "africa_countries.geojson", "south_america_countries.geojson"]
total_count = 0
ground_truth = {}

for r in regions:
    path = os.path.join(data_dir, r)
    if os.path.exists(path):
        with open(path, 'r') as f:
            data = json.load(f)
            count = len(data.get('features', []))
            ground_truth[r] = count
            total_count += count
    else:
        ground_truth[r] = 0

ground_truth["total_expected"] = total_count
ground_truth["expected_crs"] = "EPSG:4326"

with open("/tmp/ground_truth_counts.json", "w") as f:
    json.dump(ground_truth, f)

print(f"Ground Truth: {ground_truth}")
PYEOF

# Set permissions
chown -R ga:ga "/home/ga/GIS_Data"

# 5. Launch QGIS
# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Kill existing QGIS
kill_qgis ga 2>/dev/null || true

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS to be ready
wait_for_window "QGIS" 45

# Maximize window
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="