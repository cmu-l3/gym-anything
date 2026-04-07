#!/bin/bash
echo "=== Setting up multisite_research_network task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Record task start time (for anti-gaming timestamp verification)
date +%s > /tmp/task_start_timestamp

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure baseline default configuration is present
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Clean slate: Remove target QTH and Module files to prevent false positives from previous runs
rm -f "${GPREDICT_CONF_DIR}/MIT_Haystack.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Stanford_SRL.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/GaTech_SSDL.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/mit_haystack.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/stanford_srl.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/gatech_ssdl.qth" 2>/dev/null || true

rm -f "${GPREDICT_MOD_DIR}/StationKeeping.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/CubeSat_Comms.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/NOAA_APT.mod" 2>/dev/null || true

# Pre-load all required TLE datasets into the cache so the agent can find the satellites
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
for file in amateur.txt weather.txt stations.txt; do
    if [ -f "/workspace/data/$file" ]; then
        cp "/workspace/data/$file" "${GPREDICT_CONF_DIR}/satdata/cache/"
    fi
done
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true

# Update default QTH
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    else
        echo "DEFAULT_QTH=Pittsburgh.qth" >> "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Launch GPredict
echo "Starting GPredict..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid gpredict > /tmp/gpredict_task.log 2>&1 &"
sleep 5

# Wait for GPredict window
for i in {1..30}; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l | grep -i "Gpredict" | awk '{print $1}' | head -1) || true
    if [ -n "$WID" ]; then
        echo "GPredict window found (WID: $WID)"
        break
    fi
    sleep 1
done

if [ -n "$WID" ]; then
    # Maximize and focus
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -a "$WID" 2>/dev/null || true
    # Dismiss any startup tips/dialogs
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== multisite_research_network task setup complete ==="