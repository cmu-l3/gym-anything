#!/bin/bash
echo "=== Setting up Pole of Inaccessibility task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if utils not loaded
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi

# Ensure data directory exists
DATA_DIR="/home/ga/GIS_Data"
mkdir -p "$DATA_DIR"
mkdir -p "$DATA_DIR/exports"

# Download Natural Earth Countries if missing
NE_FILE="$DATA_DIR/ne_110m_admin_0_countries.geojson"
if [ ! -f "$NE_FILE" ]; then
    echo "Downloading Natural Earth countries dataset..."
    wget -q -O "$NE_FILE" "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson" || \
    echo "Error downloading dataset"
    chown ga:ga "$NE_FILE"
fi

# Clean up previous outputs
rm -f "$DATA_DIR/exports/somalia_pole.geojson" 2>/dev/null || true
rm -f "$DATA_DIR/exports/distance_report.txt" 2>/dev/null || true
chown -R ga:ga "$DATA_DIR/exports"

# Record baseline state
echo "0" > /tmp/initial_export_count
ls -1 "$DATA_DIR/exports"/* 2>/dev/null | wc -l > /tmp/initial_export_count || echo "0" > /tmp/initial_export_count

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure QGIS is fresh
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS to appear
sleep 5
wait_for_window "QGIS" 60
sleep 3

# Maximize
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Input data located at: $NE_FILE"