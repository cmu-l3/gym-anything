#!/bin/bash
set -e
echo "=== Setting up Convex Hull task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Define paths
NE_DIR="/home/ga/GIS_Data/natural_earth"
EXPORT_DIR="/home/ga/GIS_Data/exports"

# Create directories
su - ga -c "mkdir -p '$NE_DIR' '$EXPORT_DIR'"

# Download Natural Earth populated places if not present
NE_URL="https://naciscdn.org/naturalearth/10m/cultural/ne_10m_populated_places_simple.zip"
NE_ZIP="/tmp/ne_populated_places.zip"

if [ ! -f "$NE_DIR/ne_10m_populated_places_simple.shp" ]; then
    echo "Downloading Natural Earth data..."
    # Try curl, fall back to wget
    if command -v curl >/dev/null; then
        curl -L -o "$NE_ZIP" "$NE_URL" --retry 3 --retry-delay 5
    else
        wget -O "$NE_ZIP" "$NE_URL"
    fi
    
    # Unzip
    unzip -o "$NE_ZIP" -d "$NE_DIR/"
    rm -f "$NE_ZIP"
    
    # Fix permissions
    chown -R ga:ga "$NE_DIR"
fi

# Clean up previous exports to ensure fresh start
rm -f "$EXPORT_DIR/australia_convex_hull.geojson"
rm -f "$EXPORT_DIR/australia_hull_report.txt"

# Ensure QGIS is running and clean
if is_qgis_running; then
    kill_qgis ga
    sleep 2
fi

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis --noversioncheck --noplugins > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS to start
wait_for_window "QGIS" 60
sleep 5

# Maximize window
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any startup dialogs (like "tips")
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Data location: $NE_DIR/ne_10m_populated_places_simple.shp"