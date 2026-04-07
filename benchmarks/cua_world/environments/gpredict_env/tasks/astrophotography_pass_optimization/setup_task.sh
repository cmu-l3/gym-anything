#!/bin/bash
# Setup script for astrophotography_pass_optimization task
# Sets up a clean environment with the default Pittsburgh ground station
# and ensures TLE data is pre-loaded for the target satellites.

echo "=== Setting up astrophotography_pass_optimization task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Kill any existing GPredict instance safely
pkill -x gpredict || true
sleep 2

# Ensure baseline Pittsburgh.qth is correctly installed
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Remove any target files from previous attempts
rm -f "${GPREDICT_CONF_DIR}/MaunaKea.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/maunakea.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Astro_Targets.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/astro_targets.mod" 2>/dev/null || true

# Load all TLE data to ensure the required satellites can be found by name
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
for tle_file in amateur weather stations; do
    if [ -f "/workspace/data/${tle_file}.txt" ]; then
        cp "/workspace/data/${tle_file}.txt" "${GPREDICT_CONF_DIR}/satdata/cache/"
    fi
done
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true

# Ensure gpredict.cfg exists and is reset to defaults (no predictor filtering, local time)
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^MIN_EL=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^MAX_SUN_EL=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^NUM_PASSES=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^TIME_FORMAT=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^utc=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    
    # Ensure default QTH is Pittsburgh
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    else
        sed -i '/^\[GLOBAL\]/a DEFAULT_QTH=Pittsburgh.qth' "${GPREDICT_CONF_DIR}/gpredict.cfg"
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

if [ -n "$WID" ]; then
    # Maximize window
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    # Dismiss any update/startup dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -a 'Gpredict'" 2>/dev/null || true
fi

# Take initial screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="