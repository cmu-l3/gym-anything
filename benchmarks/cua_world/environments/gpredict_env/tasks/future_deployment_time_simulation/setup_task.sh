#!/bin/bash
# Setup script for future_deployment_time_simulation task
# Persona: Aerospace engineer planning future operations
# Cleans existing QTH/modules to ensure agent builds from scratch.

echo "=== Setting up future_deployment_time_simulation task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure Pittsburgh.qth is correctly installed as the baseline
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Remove any existing Austin or Texas QTH files
rm -f "${GPREDICT_CONF_DIR}/Austin.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Austin_TX.qth" 2>/dev/null || true

# Remove Deployment_Sim module if it exists
rm -f "${GPREDICT_MOD_DIR}/Deployment_Sim.mod" 2>/dev/null || true

# Load the stations.txt TLE data so ISS and CSS names resolve correctly
if [ -f /workspace/data/stations.txt ]; then
    mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
    cp /workspace/data/stations.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
    chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"
fi

# Ensure gpredict.cfg does NOT have UTC time enabled (default to local)
# and ensure Pittsburgh is the default QTH
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^utc=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    else
        sed -i '/^\[GLOBAL\]/a DEFAULT_QTH=Pittsburgh.qth' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Record baseline state
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

if [ -z "$WID" ]; then
    echo "WARNING: GPredict window not found after ${TIMEOUT}s"
    cat /tmp/gpredict_task.log 2>/dev/null || true
else
    # Maximize window
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    # Dismiss any update dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== future_deployment_time_simulation task setup complete ==="