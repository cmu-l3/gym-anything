#!/bin/bash
# Setup script for saa_radiation_pass_analysis task
# Sets up default GPredict. Removes any preexisting SAA or Tristan files.
# Resets global preferences to ensure the agent has to change them.

echo "=== Setting up saa_radiation_pass_analysis task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Clean up any potential previous task artifacts
rm -f "${GPREDICT_CONF_DIR}/Tristan_da_Cunha.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/tristan.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/SAA_Targets.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/saa.mod" 2>/dev/null || true

# Ensure Pittsburgh.qth is correctly installed (baseline station)
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Load TLE data (contains weather satellites)
if [ -f /workspace/data/weather.txt ]; then
    mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
    cp /workspace/data/weather.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
    cp /workspace/data/stations.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
    cp /workspace/data/amateur.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
    chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"
    echo "Weather satellite TLE data loaded."
fi

# Reset GPredict global config to ensure settings start off/default
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"
if [ -f "$GPREDICT_CFG" ]; then
    # Remove existing keys we are testing
    sed -i '/^PRED_PASSES=/d' "$GPREDICT_CFG"
    sed -i '/^MAP_DRAW_GRID=/d' "$GPREDICT_CFG"
    sed -i '/^MAP_DRAW_TERM=/d' "$GPREDICT_CFG"
    
    # Ensure default QTH is Pittsburgh
    if grep -q "^DEFAULT_QTH=" "$GPREDICT_CFG"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "$GPREDICT_CFG"
    fi
fi

# Ensure Amateur.mod is present so the UI isn't empty
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    mkdir -p "${GPREDICT_MOD_DIR}"
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Record start time for anti-gaming
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

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== saa_radiation_pass_analysis task setup complete ==="