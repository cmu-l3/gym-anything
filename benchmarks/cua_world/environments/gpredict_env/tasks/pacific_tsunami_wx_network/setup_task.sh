#!/bin/bash
# Setup script for pacific_tsunami_wx_network task
# Persona: NOAA PTWC satellite data technician
# Sets up a clean environment requiring the configuration of a complex,
# geographically dispersed ground station network across hemispheres.

echo "=== Setting up pacific_tsunami_wx_network task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any running GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure baseline Pittsburgh.qth exists and clean up targets
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi
rm -f "${GPREDICT_CONF_DIR}/Ewa_Beach.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Tiyan.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Pago_Pago.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/PacificWX.mod" 2>/dev/null || true

# Preload TLE data to ensure satellites are findable by name
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
if [ -f /workspace/data/weather.txt ]; then
    cp /workspace/data/weather.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
    chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"
fi

# Reset default QTH to Pittsburgh and ensure metric units are disabled to start
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^DEFAULT_QTH=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    echo "DEFAULT_QTH=Pittsburgh.qth" >> "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^unit=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

# Launch GPredict
echo "Starting GPredict..."
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
else
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="