#!/bin/bash
# Setup script for star_party_visual_passes task

echo "=== Setting up star_party_visual_passes task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"
OUTPUT_DIR="/home/ga/Documents"

# Ensure output directory exists and is clean
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/iss_visible_passes.txt"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Clean out any Griffith QTH files to ensure a fresh start
rm -f "${GPREDICT_CONF_DIR}/Griffith.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Griffith_Observatory.qth" 2>/dev/null || true

# Ensure Pittsburgh.qth is correctly installed as the default baseline
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Update default QTH
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Ensure Amateur.mod is present and contains ISS
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    mkdir -p "${GPREDICT_MOD_DIR}"
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Load the stations.txt TLE data (contains ISS) to ensure data is fresh
if [ -f /workspace/data/stations.txt ]; then
    mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
    cp /workspace/data/stations.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
    chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"
fi

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Launch GPredict
echo "Launching GPredict..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid gpredict > /tmp/gpredict_task.log 2>&1 &"
sleep 5

# Wait for GPredict window
TIMEOUT=30
ELAPSED=0
WID=""
while [ $ELAPSED -lt $TIMEOUT ]; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Gpredict" 2>/dev/null | head -1) || true
    if [ -n "$WID" ]; then
        echo "GPredict window found (WID: $WID)"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ -n "$WID" ]; then
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== star_party_visual_passes task setup complete ==="