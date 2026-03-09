#!/bin/bash
echo "=== Setting up supply_chain_hub_lines task ==="

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

# 1. Prepare Data Directory
DATA_DIR="/home/ga/GIS_Data/logistics"
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$DATA_DIR"
mkdir -p "$EXPORT_DIR"

# 2. Create Warehouses Data (2 Hubs)
cat > "$DATA_DIR/warehouses.geojson" << 'EOF'
{
  "type": "FeatureCollection",
  "name": "warehouses",
  "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
  "features": [
    { "type": "Feature", "properties": { "id": 1, "name": "Oakland Port", "type": "Maritime" }, "geometry": { "type": "Point", "coordinates": [-122.3, 37.8] } },
    { "type": "Feature", "properties": { "id": 2, "name": "SFO Cargo", "type": "Air" }, "geometry": { "type": "Point", "coordinates": [-122.38, 37.62] } }
  ]
}
EOF

# 3. Create Retail Stores Data (6 Spokes)
cat > "$DATA_DIR/retail_stores.geojson" << 'EOF'
{
  "type": "FeatureCollection",
  "name": "retail_stores",
  "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
  "features": [
    { "type": "Feature", "properties": { "id": 101, "store_name": "SF Downtown" }, "geometry": { "type": "Point", "coordinates": [-122.40, 37.78] } },
    { "type": "Feature", "properties": { "id": 102, "store_name": "Berkeley" }, "geometry": { "type": "Point", "coordinates": [-122.27, 37.87] } },
    { "type": "Feature", "properties": { "id": 103, "store_name": "San Mateo" }, "geometry": { "type": "Point", "coordinates": [-122.30, 37.55] } },
    { "type": "Feature", "properties": { "id": 104, "store_name": "Daly City" }, "geometry": { "type": "Point", "coordinates": [-122.47, 37.68] } },
    { "type": "Feature", "properties": { "id": 105, "store_name": "Hayward" }, "geometry": { "type": "Point", "coordinates": [-122.08, 37.67] } },
    { "type": "Feature", "properties": { "id": 106, "store_name": "Redwood City" }, "geometry": { "type": "Point", "coordinates": [-122.23, 37.48] } }
  ]
}
EOF

# Set permissions
chown -R ga:ga "/home/ga/GIS_Data"

# 4. Remove previous outputs
rm -f "$EXPORT_DIR/hub_connections.geojson" 2>/dev/null || true

# 5. Record Baseline State
date +%s > /tmp/task_start_timestamp

# 6. Ensure Clean QGIS State
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS window
sleep 5
wait_for_window "QGIS" 45
sleep 3

# Maximize Window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "QGIS" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -ia "$WID"
fi

take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="