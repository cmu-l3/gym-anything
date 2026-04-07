#!/bin/bash
# setup_task.sh — Facility Floorplan Mapping
# Creates sample floorplan PNG files and waits for OpManager readiness.

source /workspace/scripts/task_utils.sh

echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=180
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] WARNING: OpManager not ready after ${WAIT_TIMEOUT}s. Continuing..." >&2
        break
    fi
done
echo "[setup] OpManager is ready."

# ------------------------------------------------------------
# Generate sample floorplan images on the Desktop
# ------------------------------------------------------------
echo "[setup] Generating architectural floorplan images..."
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

# Generate main_floorplan.png
su - ga -c "convert -size 1024x768 xc:lightblue \
    -fill white -stroke black -draw \"rectangle 100,100 400,300\" \
    -fill black -stroke none -pointsize 24 -draw \"text 150,150 'Server Room A'\" \
    -fill white -stroke black -draw \"rectangle 500,100 900,600\" \
    -fill black -stroke none -pointsize 24 -draw \"text 600,350 'NOC Operations'\" \
    $DESKTOP_DIR/main_floorplan.png" 2>/dev/null || true

# Generate dr_floorplan.png
su - ga -c "convert -size 1024x768 xc:lightgreen \
    -fill white -stroke black -draw \"rectangle 200,200 800,500\" \
    -fill black -stroke none -pointsize 24 -draw \"text 300,350 'Disaster Recovery Data Center'\" \
    $DESKTOP_DIR/dr_floorplan.png" 2>/dev/null || true

# Fallback text files in case ImageMagick fails
if [ ! -f "$DESKTOP_DIR/main_floorplan.png" ]; then
    echo "Simulated floorplan image" > "$DESKTOP_DIR/main_floorplan.png"
    echo "Simulated floorplan image" > "$DESKTOP_DIR/dr_floorplan.png"
fi

chown ga:ga "$DESKTOP_DIR"/*.png 2>/dev/null || true
echo "[setup] Floorplan images generated on Desktop."

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/floorplan_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/floorplan_setup_screenshot.png" || true

echo "[setup] facility_floorplan_mapping setup complete."