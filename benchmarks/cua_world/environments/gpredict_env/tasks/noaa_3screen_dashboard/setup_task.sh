#!/bin/bash
echo "=== Setting up noaa_3screen_dashboard task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Remove Miami QTH if any to ensure clean state
rm -f "${GPREDICT_CONF_DIR}/Miami_NHC.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Miami.qth" 2>/dev/null || true

# Remove target modules if any exist
rm -f "${GPREDICT_MOD_DIR}/Global_Wx.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Radar_Wx.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Schedule_Wx.mod" 2>/dev/null || true

# Ensure Amateur.mod is present (the agent must delete it)
mkdir -p "${GPREDICT_MOD_DIR}"
if [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Ensure default Pittsburgh QTH is present
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Clean gpredict.cfg to ensure defaults (no UTC, default orbits)
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^utc=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/orbit/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/track/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

# Load TLE data cache so satellites are resolvable
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
if [ -f /workspace/data/weather.txt ]; then
    cp /workspace/data/weather.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
    chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"
fi

# Record start time for verification
date +%s > /tmp/task_start_timestamp

# Start GPredict
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
fi

DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup complete ==="