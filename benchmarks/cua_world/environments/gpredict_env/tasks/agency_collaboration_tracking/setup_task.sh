#!/bin/bash
# Setup script for agency_collaboration_tracking task

echo "=== Setting up agency_collaboration_tracking task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure Pittsburgh.qth is correctly installed (baseline)
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Remove any target QTH files and modules (clean start)
rm -f "${GPREDICT_CONF_DIR}/Geneva.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Beijing.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/NASA_Assets.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/CNSA_Assets.mod" 2>/dev/null || true

# Ensure Amateur.mod is present (the agent must delete it)
mkdir -p "${GPREDICT_MOD_DIR}"
if [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
else
    # Fallback to creating a generic Amateur module
    cat > "${GPREDICT_MOD_DIR}/Amateur.mod" << 'EOF'
[MODULE]
SATELLITES=25544;7530;22825;
QTHFILE=Pittsburgh.qth
SHOWEV=1
SHOWMAP=1
SHOWPOLARPLOT=1
SHOWSKYAT=0
PANEL=0
NAME=Amateur
EOF
fi
chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
echo "Amateur.mod loaded. Agent must delete this."

# Ensure gpredict.cfg does NOT have UTC time enabled (default to local)
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^utc=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

# Record baseline task timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Load the required TLE data to cache
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
for tle_file in amateur.txt stations.txt weather.txt; do
    if [ -f "/workspace/data/$tle_file" ]; then
        cp "/workspace/data/$tle_file" "${GPREDICT_CONF_DIR}/satdata/cache/"
    fi
done
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"
echo "TLE data loaded into GPredict cache."

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
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    # Dismiss any startup tips
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== agency_collaboration_tracking setup complete ==="