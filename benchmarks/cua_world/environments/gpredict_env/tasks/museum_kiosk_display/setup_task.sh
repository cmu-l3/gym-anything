#!/bin/bash
# Setup script for museum_kiosk_display task

echo "=== Setting up museum_kiosk_display task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure Pittsburgh.qth is correctly installed (baseline)
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Clean up any target files to ensure a fresh start
rm -f "${GPREDICT_CONF_DIR}/MSI_Chicago.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/msi_chicago.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Chicago.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Crewed_Missions.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Crewed.mod" 2>/dev/null || true

# Ensure Amateur.mod is present and is the only open module
mkdir -p "${GPREDICT_MOD_DIR}"
if [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Reset GPredict config to ensure default tracks and UI state
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    # Set Amateur.mod as the only open module
    sed -i '/^modules=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^\[GUI\]/a modules=Amateur.mod;' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    
    # Remove any existing track configurations to force defaults
    sed -i '/^TRK_/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

# Ensure TLE data is loaded for crewed space stations
if [ -f /workspace/data/stations.txt ]; then
    mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
    cp /workspace/data/stations.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
    chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"
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
else
    # Maximize window (but don't fullscreen it - the agent must do that)
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    # Dismiss any startup dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== museum_kiosk_display task setup complete ==="