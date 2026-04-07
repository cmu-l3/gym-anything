#!/bin/bash
echo "=== Setting up disaster_relief_imagery_tasking task ==="

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Directories
GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill GPredict if it's currently running
pkill -x gpredict || true
sleep 2

# Set up baseline QTH (Pittsburgh) to ensure standard starting point
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Clean up target files to guarantee agent must create them
rm -f "${GPREDICT_CONF_DIR}/Kathmandu.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Disaster_EO.mod" 2>/dev/null || true

# Reset default QTH to baseline
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^DEFAULT_QTH=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    echo "DEFAULT_QTH=Pittsburgh.qth" >> "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

# Load TLEs so satellite names populate correctly in the search UI
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
for f in amateur.txt weather.txt stations.txt; do
    if [ -f "/workspace/data/$f" ]; then
        cp "/workspace/data/$f" "${GPREDICT_CONF_DIR}/satdata/cache/"
    fi
done
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache" 2>/dev/null || true

# Launch GPredict
echo "Launching GPredict..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid gpredict > /tmp/gpredict_task.log 2>&1 &"
sleep 5

# Wait for window to appear, focus, and maximize
for i in {1..30}; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Gpredict" 2>/dev/null | head -1) || true
    if [ -n "$WID" ]; then
        echo "GPredict window found (WID: $WID)"
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 1
        # Dismiss any welcome dialogs
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot for framework logs
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true
echo "=== Task setup complete ==="