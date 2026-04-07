#!/bin/bash
# Setup script for multicampus_qth_binding task
# Ensures a clean GPredict environment with only default configurations.

echo "=== Setting up multicampus_qth_binding task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# 1. Kill any existing GPredict instance cleanly
pkill -x gpredict || true
sleep 2

# 2. Reset configurations to baseline
# Ensure baseline Pittsburgh QTH is present
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Remove any target QTH files if they exist from a previous run
rm -f "${GPREDICT_CONF_DIR}/CU_Boulder.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/CSU_FortCollins.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Mines_Golden.qth" 2>/dev/null || true

# Remove any target MOD files if they exist
rm -f "${GPREDICT_MOD_DIR}/CU_Boulder.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/CSU_FortCollins.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Mines_Golden.mod" 2>/dev/null || true

# Ensure Amateur.mod is present
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    mkdir -p "${GPREDICT_MOD_DIR}"
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Reset default QTH and time settings in gpredict.cfg
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^utc=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

# 3. Load the TLE data for the required satellites
if [ -d /workspace/data ]; then
    mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
    cp /workspace/data/stations.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
    cp /workspace/data/amateur.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
    chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"
    echo "Satellite TLE data loaded."
fi

# 4. Record task start time and baseline files for anti-gaming verification
date +%s > /tmp/task_start_timestamp
ls -la "${GPREDICT_CONF_DIR}/"*.qth 2>/dev/null > /tmp/initial_qth_files.txt
ls -la "${GPREDICT_MOD_DIR}/"*.mod 2>/dev/null > /tmp/initial_mod_files.txt

# 5. Launch GPredict
echo "Launching GPredict..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid gpredict > /tmp/gpredict_task.log 2>&1 &"
sleep 5

# 6. Wait for GPredict window and focus it
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

# 7. Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="