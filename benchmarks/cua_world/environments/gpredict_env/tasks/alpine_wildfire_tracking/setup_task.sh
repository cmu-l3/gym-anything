#!/bin/bash
echo "=== Setting up alpine_wildfire_tracking task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Remove any existing Santiago QTH files or Fire Orbits modules to ensure clean state
rm -f "${GPREDICT_CONF_DIR}/Santiago_Valley.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/santiago"*.qth 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Fire_Orbits.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/fire"*.mod 2>/dev/null || true

# Ensure baseline Pittsburgh.qth is present
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Ensure TLE data is loaded into cache so agent can find the weather satellites
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
if [ -f /workspace/data/weather.txt ]; then
    cp /workspace/data/weather.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
    chown ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/weather.txt"
fi
if [ -f /workspace/data/amateur.txt ]; then
    cp /workspace/data/amateur.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
    chown ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/amateur.txt"
fi

# Record start time for anti-gaming (ensures files are created DURING the task)
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

if [ -n "$WID" ]; then
    # Maximize window
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r $WID -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    # Dismiss any update/startup dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
else
    echo "WARNING: GPredict window not found after ${TIMEOUT}s"
fi

# Take initial screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== alpine_wildfire_tracking setup complete ==="