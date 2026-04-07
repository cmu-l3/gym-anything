#!/bin/bash
# Setup script for atmospheric_diurnal_tracking_setup task
# Cleans the environment, seeds the TLE caches, and resets preferences.

echo "=== Setting up atmospheric_diurnal_tracking_setup task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure baseline Pittsburgh.qth is installed
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Pre-load TLE data so COSMIC-2 satellites are searchable
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
cp /workspace/data/weather.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
cp /workspace/data/amateur.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
cp /workspace/data/stations.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache" 2>/dev/null || true
echo "Loaded real satellite TLE datasets into cache."

# Clean up target outputs to prevent false positives from previous runs
rm -f "${GPREDICT_CONF_DIR}/Taipei_CWA.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Taipei.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/COSMIC-2.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/COSMIC2.mod" 2>/dev/null || true

# Reset GPredict global preferences
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    # Delete metric/UTC settings to ensure agent must set them
    sed -i '/^utc=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/shadow/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/terminator/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/track/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    
    # Force default QTH back to Pittsburgh
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    else
        sed -i '/^\[GLOBAL\]/a DEFAULT_QTH=Pittsburgh.qth' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

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
    # Maximize and focus
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== atmospheric_diurnal_tracking_setup task setup complete ==="