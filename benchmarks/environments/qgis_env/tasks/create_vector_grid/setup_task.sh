#!/bin/bash
echo "=== Setting up create_vector_grid task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if utils not loaded
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

# 1. Verify input data exists
INPUT_FILE="/home/ga/GIS_Data/sample_polygon.geojson"
if [ ! -f "$INPUT_FILE" ]; then
    echo "ERROR: Input file $INPUT_FILE not found!"
    # Try to recreate it if missing (recovery strategy)
    mkdir -p /home/ga/GIS_Data
    cat > "$INPUT_FILE" << 'EOF'
{
  "type": "FeatureCollection",
  "name": "sample_polygon",
  "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
  "features": [
    { "type": "Feature", "properties": { "id": 1, "name": "Area A", "area_sqkm": 10.5 }, "geometry": { "type": "Polygon", "coordinates": [[[-122.5, 37.5], [-122.5, 37.8], [-122.2, 37.8], [-122.2, 37.5], [-122.5, 37.5]]] } },
    { "type": "Feature", "properties": { "id": 2, "name": "Area B", "area_sqkm": 8.2 }, "geometry": { "type": "Polygon", "coordinates": [[[-122.2, 37.5], [-122.2, 37.8], [-121.9, 37.8], [-121.9, 37.5], [-122.2, 37.5]]] } }
  ]
}
EOF
    chown ga:ga "$INPUT_FILE"
    echo "Recreated input file."
fi

# 2. Prepare output directory and clean state
EXPORTS_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$EXPORTS_DIR"
# Remove expected output file and any variations
rm -f "$EXPORTS_DIR/study_area_grid.geojson" 2>/dev/null || true
rm -f "$EXPORTS_DIR/study_area_grid.json" 2>/dev/null || true
rm -f "$EXPORTS_DIR/grid.geojson" 2>/dev/null || true
chown -R ga:ga "$EXPORTS_DIR"

# 3. Record initial state
date +%s > /tmp/task_start_time.txt
ls -1 "$EXPORTS_DIR"/*.geojson 2>/dev/null | wc -l > /tmp/initial_export_count.txt

# 4. Start QGIS
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for window
sleep 5
wait_for_window "QGIS" 45
sleep 3

# Maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "QGIS" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="