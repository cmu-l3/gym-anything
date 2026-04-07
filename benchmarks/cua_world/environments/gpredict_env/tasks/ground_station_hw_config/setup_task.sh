#!/bin/bash
echo "=== Setting up ground_station_hw_config task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure baseline QTH is present
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# 1. Clean up any existing AutoTrack module
rm -f "${GPREDICT_MOD_DIR}/AutoTrack.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/autotrack.mod" 2>/dev/null || true

# 2. Clean up any existing GeorgiaTech QTH
rm -f "${GPREDICT_CONF_DIR}/GeorgiaTech.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/georgiatech.qth" 2>/dev/null || true

# 3. Clean up any existing hardware interfaces
# GPredict stores these in radios/ and rotators/ directories, and also sometimes in hwconf/
rm -rf "${GPREDICT_CONF_DIR}/radios" 2>/dev/null || true
rm -rf "${GPREDICT_CONF_DIR}/rotators" 2>/dev/null || true
rm -rf "${GPREDICT_CONF_DIR}/hwconf" 2>/dev/null || true

# Recreate empty directories with proper permissions
mkdir -p "${GPREDICT_CONF_DIR}/radios"
mkdir -p "${GPREDICT_CONF_DIR}/rotators"
chown -R ga:ga "${GPREDICT_CONF_DIR}/radios"
chown -R ga:ga "${GPREDICT_CONF_DIR}/rotators"

# Strip RIG/ROT references from gpredict.cfg if they exist
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^RIG_/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^ROT_/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

# Ensure TLE data is available for the required satellites
if [ -f /workspace/data/amateur.txt ]; then
    mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
    cp /workspace/data/amateur.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
    cp /workspace/data/stations.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
    chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache"
fi

# Ensure Amateur module exists so UI is fully populated initially
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    mkdir -p "${GPREDICT_MOD_DIR}"
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Set default QTH
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Take snapshot of clean state for anti-gaming comparison
ls -la "${GPREDICT_CONF_DIR}/radios/" > /tmp/gpredict_radios_initial.txt 2>/dev/null || true

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
    # Dismiss any startup tips/dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="