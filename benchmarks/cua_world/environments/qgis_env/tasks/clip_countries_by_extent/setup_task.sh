#!/bin/bash
echo "=== Setting up clip_countries_by_extent task ==="

source /workspace/scripts/task_utils.sh

# Fallback for task_utils if not available
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

# 1. Prepare Data: Download Natural Earth 110m Countries if missing
DATA_DIR="/home/ga/GIS_Data/natural_earth"
SHP_FILE="$DATA_DIR/ne_110m_admin_0_countries.shp"
mkdir -p "$DATA_DIR"

if [ ! -f "$SHP_FILE" ]; then
    echo "Downloading Natural Earth dataset..."
    # Use a reliable source for the dataset
    ZIP_FILE="$DATA_DIR/ne_110m.zip"
    
    # Try official source
    wget -q -O "$ZIP_FILE" "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip" || \
    # Fallback to a mirror or alternate if official fails (mocking the fallback here)
    echo "Download failed from primary source."

    if [ -f "$ZIP_FILE" ]; then
        unzip -o -q "$ZIP_FILE" -d "$DATA_DIR"
        rm "$ZIP_FILE"
        # Ensure permissions are correct
        chown -R ga:ga "$DATA_DIR"
        echo "Dataset prepared."
    else
        echo "ERROR: Failed to download dataset."
        # Create a dummy shapefile if download fails to allow task to proceed (though it will likely fail verification)
        # This is a fail-safe to prevent immediate crash, but ideally we want real data.
        # For this implementation, we assume internet access is available as per env spec.
        exit 1
    fi
else
    echo "Dataset already exists."
fi

# 2. Clean up previous outputs
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/european_countries.geojson" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"

# 3. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_timestamp

# 4. Ensure QGIS is running
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS to start
sleep 5
wait_for_window "QGIS" 60
sleep 2

# Maximize window
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="