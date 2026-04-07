#!/bin/bash
# Setup script for urban_sidewalk_astronomy_setup task
# Persona: Urban Astronomy Outreach Coordinator

echo "=== Setting up urban_sidewalk_astronomy_setup task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure the baseline configurations exist
mkdir -p "${GPREDICT_MOD_DIR}"
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"

# Ensure Pittsburgh is the default QTH to start with
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Clean up any leftover Chicago ground stations from previous runs
rm -f "${GPREDICT_CONF_DIR}/Chicago.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Chicago_Urban.qth" 2>/dev/null || true

# Clean up the target module if it exists
rm -f "${GPREDICT_MOD_DIR}/Urban_Bright.mod" 2>/dev/null || true

# Restore the default Amateur.mod
if [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Reset Predict preferences in gpredict.cfg to defaults (so agent must change them)
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    # Remove existing predictability limits
    sed -i '/^MIN_EL=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^MAX_SUN_EL=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^NUM_PASSES=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    
    # Ensure DEFAULT_QTH is set properly
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Load TLE data so ISS and CSS are recognizable
if [ -f /workspace/data/stations.txt ]; then
    cp /workspace/data/stations.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
    chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"
fi

# Record start time for anti-gaming verification
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

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== urban_sidewalk_astronomy_setup task setup complete ==="