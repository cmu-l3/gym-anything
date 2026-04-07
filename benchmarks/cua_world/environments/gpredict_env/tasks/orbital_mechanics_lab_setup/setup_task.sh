#!/bin/bash
echo "=== Setting up orbital_mechanics_lab_setup task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure Amateur.mod exists (default setup that agent needs to delete)
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    mkdir -p "${GPREDICT_MOD_DIR}"
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Clean up target files to guarantee a fresh start
rm -f "${GPREDICT_MOD_DIR}/Crewed_Stations.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Polar_Weather.mod" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/MIT.qth" 2>/dev/null || true

# Reset min_el and utc in gpredict.cfg if they exist
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^MIN_EL=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^PRED_MIN_EL=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^utc=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^USE_LOCAL_TIME=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^TIME_FORMAT=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

# Ensure TLE data is loaded into the cache so satellite search works
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
for f in amateur.txt weather.txt stations.txt; do
    if [ -f "/workspace/data/$f" ]; then
        cp "/workspace/data/$f" "${GPREDICT_CONF_DIR}/satdata/cache/"
    fi
done
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

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
    # Dismiss any startup splash/dialog
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
fi

# Take initial screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="