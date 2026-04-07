#!/bin/bash
# Setup script for arctic_icebreaker_wx_tracking task
# Persona: Arctic expedition communications officer
echo "=== Setting up arctic_icebreaker_wx_tracking task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure baseline Pittsburgh.qth is correctly installed
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Clean up task-specific files to ensure agent must create them
rm -f "${GPREDICT_CONF_DIR}/RV_Polarstern.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/rv_polarstern.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Arctic_WX.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/arctic_wx.mod" 2>/dev/null || true

# Strip existing map preferences from gpredict.cfg to ensure a clean default state
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^GRID=/Id' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^TERMINATOR=/Id' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^TRACK_ORBITS=/Id' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    
    # Ensure DEFAULT_QTH is set to Pittsburgh initially
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Ensure TLE data is available
if [ -d /workspace/data ]; then
    mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
    cp /workspace/data/weather.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
    chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache"
fi

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Launch GPredict
echo "Launching GPredict..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid gpredict > /tmp/gpredict_task.log 2>&1 &"
sleep 5

# Wait for GPredict window to appear
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
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup complete ==="