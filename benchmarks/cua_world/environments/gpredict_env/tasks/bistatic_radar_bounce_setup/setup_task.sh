#!/bin/bash
# Setup script for bistatic_radar_bounce_setup task
# Persona: Radio physics lab researcher (Strasbourg)
# Sets up a clean default GPredict installation:
#   - Default Amateur module and Pittsburgh ground station
#   - Ensures all TLEs (amateur, weather, stations) are available
#   - Removes any stray configs that the agent should create

echo "=== Setting up bistatic_radar_bounce_setup task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Clean start for configurations
rm -f "${GPREDICT_CONF_DIR}/Strasbourg_RX.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/strasbourg.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/High_RCS_Targets.mod" 2>/dev/null || true

# Ensure Pittsburgh.qth is the fallback baseline
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Set default QTH to Pittsburgh
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    else
        sed -i '/^\[GLOBAL\]/a DEFAULT_QTH=Pittsburgh.qth' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
    # Reset MIN_EL to default 0 or 10
    if grep -q "^MIN_EL=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^MIN_EL=.*/MIN_EL=0/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Ensure Amateur.mod is present so there is a default tracking window
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    mkdir -p "${GPREDICT_MOD_DIR}"
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Load the comprehensive TLE data
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
for t in amateur.txt stations.txt weather.txt; do
    if [ -f "/workspace/data/$t" ]; then
        cp "/workspace/data/$t" "${GPREDICT_CONF_DIR}/satdata/cache/"
        echo "Loaded TLE data: $t"
    fi
done
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true

# Record timestamps
date +%s > /tmp/task_start_timestamp
echo "0" > /tmp/initial_min_el

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
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r $WID -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -a $WID" 2>/dev/null || true
    sleep 1
    # Dismiss any update dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== bistatic_radar_bounce_setup task setup complete ==="