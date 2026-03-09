#!/bin/bash
echo "=== Setting up georeference_map_with_saved_gcps task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if utils not loaded
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
DATA_DIR="/home/ga/GIS_Data"
EXPORT_DIR="$DATA_DIR/exports"
mkdir -p "$DATA_DIR"
mkdir -p "$EXPORT_DIR"

# 2. Generate Simulated Scanned Map (1000x1000 white image with text)
IMAGE_PATH="$DATA_DIR/historical_map.png"
echo "Generating simulated map image..."
convert -size 1000x1000 xc:white \
    -fill black -draw "rectangle 5,5 995,995" \
    -fill white -draw "rectangle 10,10 990,990" \
    -fill black -pointsize 48 -gravity center -annotate +0+0 "HISTORICAL SITE PLAN\nSan Francisco Bay Area\n1950" \
    -fill red -draw "circle 0,0 10,10" \
    -fill red -draw "circle 1000,0 990,10" \
    -fill red -draw "circle 1000,1000 990,990" \
    -fill red -draw "circle 0,1000 10,990" \
    "$IMAGE_PATH"

# 3. Generate GCP Points File
# Format: mapX,mapY,pixelX,pixelY,enable
# Mapping:
# TL (0,0)       -> -122.5, 37.8
# TR (1000,0)    -> -122.4, 37.8
# BR (1000,1000) -> -122.4, 37.7
# BL (0,1000)    -> -122.5, 37.7
POINTS_PATH="$DATA_DIR/historical_map.png.points"
echo "Generating GCP points file..."
cat > "$POINTS_PATH" << EOF
mapX,mapY,pixelX,pixelY,enable
-122.5,37.8,0,0,1
-122.4,37.8,1000,0,1
-122.4,37.7,1000,1000,1
-122.5,37.7,0,1000,1
EOF

# Set permissions
chown -R ga:ga "$DATA_DIR"

# 4. Cleanup previous outputs
rm -f "$EXPORT_DIR/historical_map_georeferenced.tif" 2>/dev/null || true

# 5. Record task start time
date +%s > /tmp/task_start_time.txt

# 6. Ensure QGIS is running
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS
sleep 5
wait_for_window "QGIS" 45
sleep 3

# Maximize QGIS
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Data created at $IMAGE_PATH"
echo "GCPs created at $POINTS_PATH"