#!/bin/bash
echo "=== Setting up heatmap_kde_population task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if task_utils not available
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

# 1. Prepare Data Directory
DATA_DIR="/home/ga/GIS_Data/natural_earth"
mkdir -p "$DATA_DIR"
mkdir -p "/home/ga/GIS_Data/exports"
mkdir -p "/home/ga/GIS_Data/projects"

# 2. Download Real Data (Natural Earth Populated Places)
SHP_FILE="$DATA_DIR/ne_110m_populated_places_simple.shp"
ZIP_FILE="$DATA_DIR/populated_places.zip"

if [ ! -f "$SHP_FILE" ]; then
    echo "Downloading Natural Earth populated places data..."
    # Use reliable source (Natural Earth CDN)
    if wget -q -O "$ZIP_FILE" "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_populated_places_simple.zip"; then
        echo "Download successful, unzipping..."
        unzip -o -q "$ZIP_FILE" -d "$DATA_DIR"
        rm -f "$ZIP_FILE"
    else
        echo "ERROR: Failed to download dataset. Using fallback generation."
        # Fallback: Generate a shapefile with Python if download fails
        # This ensures the task is runnable even if network is flaky, 
        # but attempts real data first per requirements.
        cat > "$DATA_DIR/generate_mock.py" << 'PYEOF'
import json
import random

geojson = {
    "type": "FeatureCollection",
    "features": []
}
# Generate 50 points roughly resembling world cities
for i in range(50):
    lon = random.uniform(-180, 180)
    lat = random.uniform(-60, 70)
    pop = random.randint(100000, 10000000)
    geojson["features"].append({
        "type": "Feature",
        "properties": {"name": f"City_{i}", "pop_max": pop},
        "geometry": {"type": "Point", "coordinates": [lon, lat]}
    })

with open("mock_places.geojson", "w") as f:
    json.dump(geojson, f)
PYEOF
        cd "$DATA_DIR"
        python3 generate_mock.py
        # Convert to shapefile using ogr2ogr
        ogr2ogr -f "ESRI Shapefile" ne_110m_populated_places_simple.shp mock_places.geojson
        rm -f mock_places.geojson generate_mock.py
    fi
fi

# Ensure permissions
chown -R ga:ga "/home/ga/GIS_Data"

# 3. Clean up previous results
rm -f "/home/ga/GIS_Data/exports/population_heatmap.tif" 2>/dev/null || true
rm -f "/home/ga/GIS_Data/projects/heatmap_project.qgz" 2>/dev/null || true
rm -f "/home/ga/GIS_Data/projects/heatmap_project.qgs" 2>/dev/null || true

# 4. Record task start time
date +%s > /tmp/task_start_timestamp

# 5. Launch QGIS
echo "Restarting QGIS..."
kill_qgis ga 2>/dev/null || true
sleep 1

su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for window
sleep 5
wait_for_window "QGIS" 45
sleep 3

# Maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "QGIS" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Data available at: $SHP_FILE"