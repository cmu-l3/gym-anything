#!/bin/bash
# Setup script for remote_island_dxpedition task
# Persona: DXpedition Team Lead
# Sets up default GPredict installation, ensuring NO target files exist yet.

echo "=== Setting up remote_island_dxpedition task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure Pittsburgh.qth is installed (baseline station)
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# 1. Ensure target ground stations do NOT exist
rm -f "${GPREDICT_CONF_DIR}/Sable_Island.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/SableIsland.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Sable.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Halifax.qth" 2>/dev/null || true

# 2. Ensure target module does NOT exist
rm -f "${GPREDICT_MOD_DIR}/DXpedition.mod" 2>/dev/null || true

# 3. Ensure Amateur.mod DOES exist (agent must delete it)
mkdir -p "${GPREDICT_MOD_DIR}"
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Load the stations.txt and amateur.txt TLE data to ensure satellite names resolve
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
if [ -f /workspace/data/stations.txt ]; then
    cp /workspace/data/stations.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
fi
if [ -f /workspace/data/amateur.txt ]; then
    cp /workspace/data/amateur.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
fi
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Update default QTH
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

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

if [ -z "$WID" ]; then
    echo "WARNING: GPredict window not found after ${TIMEOUT}s"
    cat /tmp/gpredict_task.log 2>/dev/null || true
else
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== remote_island_dxpedition task setup complete ==="
echo "Starting state:"
echo "  - Amateur.mod: Present (must be deleted)"
echo "  - DXpedition.mod: Missing (must be created)"
echo "  - Sable_Island.qth: Missing (must be created)"
echo "  - Halifax.qth: Missing (must be created)"