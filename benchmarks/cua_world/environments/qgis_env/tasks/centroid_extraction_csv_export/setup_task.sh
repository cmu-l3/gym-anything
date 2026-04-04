#!/bin/bash
echo "=== Setting up centroid_extraction_csv_export task ==="

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

# 1. Prepare Data
DATA_DIR="/home/ga/GIS_Data/natural_earth"
mkdir -p "$DATA_DIR"

SHP_FILE="$DATA_DIR/ne_110m_admin_0_countries.shp"

if [ ! -f "$SHP_FILE" ]; then
    echo "Downloading Natural Earth Countries dataset..."
    ZIP_FILE="$DATA_DIR/ne_110m_admin_0_countries.zip"
    
    # Try reliable mirror first, fallback to official if needed
    wget -q -O "$ZIP_FILE" "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip" || \
    echo "Failed to download data"
    
    if [ -f "$ZIP_FILE" ]; then
        unzip -o "$ZIP_FILE" -d "$DATA_DIR"
        rm "$ZIP_FILE"
    fi
fi

# Set permissions
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# 2. Prepare Output Directory
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$EXPORT_DIR"
# Clean previous output
rm -f "$EXPORT_DIR/south_america_centroids.csv" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR" 2>/dev/null || true

# 3. Record Baseline
ls -1 "$EXPORT_DIR"/*.csv 2>/dev/null | wc -l > /tmp/initial_csv_count || echo "0" > /tmp/initial_csv_count
echo "Initial CSV count: $(cat /tmp/initial_csv_count)"

# 4. Record Timestamp
date +%s > /tmp/task_start_timestamp

# 5. Launch QGIS
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for window
sleep 5
wait_for_window "QGIS" 40
sleep 3

# Maximize
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="