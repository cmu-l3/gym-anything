#!/bin/bash
# Setup script for sota_high_altitude_expedition task
# Persona: SOTA (Summits on the Air) operator preparing offline laptop
# Starting state:
#   - Default GPredict installation
#   - NO Mt_Whitney ground station
#   - NO SOTA_FM module
#   - Default map (earth.png), NO auto-updates

echo "=== Setting up sota_high_altitude_expedition task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Clean up any potential artifacts from previous runs
rm -f "${GPREDICT_CONF_DIR}/Mt_Whitney.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/MtWhitney.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Whitney.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/SOTA_FM.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/SOTA.mod" 2>/dev/null || true

# Strip any auto-update or map configurations from gpredict.cfg to ensure a clean slate
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^AUTO_UPDATE=/Id' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^MAP_FILE=/Id' "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

# Ensure Amateur.mod is present to serve as the default launch state
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    mkdir -p "${GPREDICT_MOD_DIR}"
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Record start time for anti-gaming verification
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

if [ -z "$WID" ]; then
    echo "WARNING: GPredict window not found after ${TIMEOUT}s"
    cat /tmp/gpredict_task.log 2>/dev/null || true
else
    # Maximize window
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    # Dismiss any startup tips or warnings
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== sota_high_altitude_expedition task setup complete ==="