#!/bin/bash
# Setup script for full_duplex_crossband_setup task

echo "=== Setting up full_duplex_crossband_setup task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Clean start for radios and rotators to prevent pre-existing interference
rm -rf "${GPREDICT_CONF_DIR}/radios" 2>/dev/null || true
rm -rf "${GPREDICT_CONF_DIR}/rotators" 2>/dev/null || true
mkdir -p "${GPREDICT_CONF_DIR}/radios"
mkdir -p "${GPREDICT_CONF_DIR}/rotators"
chown -R ga:ga "${GPREDICT_CONF_DIR}/radios" "${GPREDICT_CONF_DIR}/rotators"

# Remove the target module if it somehow exists
rm -f "${GPREDICT_MOD_DIR}/Linear_SSB.mod" 2>/dev/null || true

# Ensure Pittsburgh.qth is correctly installed (baseline ground station)
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Load TLE data (stations + amateur + weather) so satellite names resolve correctly
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
for f in amateur.txt weather.txt stations.txt; do
    if [ -f "/workspace/data/$f" ]; then
        cp "/workspace/data/$f" "${GPREDICT_CONF_DIR}/satdata/cache/"
    fi
done
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache"

# Ensure Amateur.mod is present so the agent has a starting module open
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    mkdir -p "${GPREDICT_MOD_DIR}"
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Record task start time (anti-gaming verification)
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
else
    # Maximize and focus
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r $WID -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    # Dismiss any update/first-launch dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Capture initial state screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="