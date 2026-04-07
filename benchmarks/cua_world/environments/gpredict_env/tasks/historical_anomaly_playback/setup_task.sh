#!/bin/bash
echo "=== Setting up historical_anomaly_playback task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
rm -f /home/ga/incident_reconstruction.png

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Clean up any potential artifacts from previous runs
rm -f "${GPREDICT_CONF_DIR}/Tromso.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/tromso.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Incident_Recon.mod" 2>/dev/null || true

# Ensure baseline Pittsburgh.qth is present
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Load TLE data (specifically weather.txt for SUOMI NPP and DMSP F18)
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
if [ -f /workspace/data/weather.txt ]; then
    cp /workspace/data/weather.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
fi
if [ -f /workspace/data/amateur.txt ]; then
    cp /workspace/data/amateur.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
fi
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
echo "TLE data loaded into cache."

# Ensure metric units NOT enabled and UTC time NOT enabled by default
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^utc=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

# Set default QTH to Pittsburgh
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
    # Maximize window
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    # Dismiss any startup dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="