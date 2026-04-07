#!/bin/bash
echo "=== Setting up observation_night_layout task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Clean up task-specific targets
rm -f "${GPREDICT_MOD_DIR}/BrightSats.mod" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/CherrySprings.qth" 2>/dev/null || true

# Install Pittsburgh as default ground station
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Ensure Amateur.mod is present and strictly set to 1-view Map layout
mkdir -p "${GPREDICT_MOD_DIR}"
if [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

if [ -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    # Force single Map view layout so agent must change it to 3-view
    sed -i 's/^NVIEWS=.*/NVIEWS=1/' "${GPREDICT_MOD_DIR}/Amateur.mod"
    sed -i 's/^VIEW_1=.*/VIEW_1=0/' "${GPREDICT_MOD_DIR}/Amateur.mod"
    # Remove any extra view lines
    sed -i '/^VIEW_[234]=/d' "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Load TLE data to cache for satellite searching
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
for txt in amateur.txt stations.txt weather.txt; do
    if [ -f "/workspace/data/$txt" ]; then
        cp "/workspace/data/$txt" "${GPREDICT_CONF_DIR}/satdata/cache/"
    fi
done
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true

# Turn off UTC time if it's on
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^utc=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    # Ensure default QTH
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Record baseline state for anti-gaming verification
echo "$(date +%s)" > /tmp/task_start_timestamp
grep -i "^SATELLITES=" "${GPREDICT_MOD_DIR}/Amateur.mod" | cut -d= -f2 > /tmp/amateur_initial_sats

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
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ -n "$WID" ]; then
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== observation_night_layout setup complete ==="