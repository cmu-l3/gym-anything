#!/bin/bash
echo "=== Setting up megacity_country_summary task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi

DATA_DIR="/home/ga/GIS_Data"
mkdir -p "$DATA_DIR/exports"
chown -R ga:ga "$DATA_DIR"

# Download Natural Earth data if missing
# Admin 0 - Countries
if [ ! -f "$DATA_DIR/ne_110m_admin_0_countries.geojson" ]; then
    echo "Downloading countries dataset..."
    wget -q -O "$DATA_DIR/ne_110m_admin_0_countries.geojson" \
        "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson"
fi

# Populated Places
if [ ! -f "$DATA_DIR/ne_110m_populated_places.geojson" ]; then
    echo "Downloading populated places dataset..."
    wget -q -O "$DATA_DIR/ne_110m_populated_places.geojson" \
        "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_populated_places.geojson"
fi

# Ensure permissions
chown ga:ga "$DATA_DIR"/*.geojson

# Clean previous output
rm -f "$DATA_DIR/exports/megacity_stats_by_country.geojson" 2>/dev/null || true

# Record initial state
date +%s > /tmp/task_start_timestamp

# Kill any running QGIS
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for window
sleep 5
wait_for_window "QGIS" 45
sleep 3

# Maximize
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="