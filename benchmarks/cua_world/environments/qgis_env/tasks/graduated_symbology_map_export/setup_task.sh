#!/bin/bash
echo "=== Setting up graduated_symbology_map_export task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Data
DATA_DIR="/home/ga/GIS_Data"
DATA_FILE="$DATA_DIR/ne_110m_admin_0_countries.geojson"
PROJECT_DIR="$DATA_DIR/projects"
EXPORT_DIR="$DATA_DIR/exports"

mkdir -p "$PROJECT_DIR"
mkdir -p "$EXPORT_DIR"
chown -R ga:ga "$DATA_DIR"

# Download Natural Earth data if missing
if [ ! -f "$DATA_FILE" ]; then
    echo "Downloading Natural Earth countries data..."
    # Use a reliable mirror for the GeoJSON
    wget -q -O "$DATA_FILE" "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson" || \
    echo "Failed to download data. Creating placeholder for offline testing (NOT IDEAL)."
    
    # Verify download size (should be ~2.5MB)
    FILE_SIZE=$(stat -c%s "$DATA_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -lt 1000 ]; then
        echo "WARNING: Data file seems too small or failed to download."
    fi
    chown ga:ga "$DATA_FILE"
fi

# 2. Cleanup previous runs
rm -f "$PROJECT_DIR/world_population_map.qgz" 2>/dev/null || true
rm -f "$PROJECT_DIR/world_population_map.qgs" 2>/dev/null || true
rm -f "$EXPORT_DIR/world_population_map.png" 2>/dev/null || true

# 3. Record start state
date +%s > /tmp/task_start_timestamp

# 4. Launch QGIS
# Kill any existing instances to ensure clean state
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS to be ready
wait_for_window "QGIS" 40
sleep 2

# Maximize window
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Capture initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Data available at: $DATA_FILE"