#!/bin/bash
# Setup script for urban_canyon_high_passes task
echo "=== Setting up urban_canyon_high_passes task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure the configuration directories exist
mkdir -p "${GPREDICT_MOD_DIR}"

# 1. Provide the legacy Pittsburgh QTH
cat > "${GPREDICT_CONF_DIR}/Pittsburgh.qth" << 'EOF'
[GROUND STATION]
LOCATION=Pittsburgh, PA
LAT=40.440600
LON=-79.995900
ALT=230
WX=KPIT
GPSD_SERVER=
GPSD_PORT=2947
EOF
chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"

# 2. Provide the legacy Amateur module
if [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
else
    cat > "${GPREDICT_MOD_DIR}/Amateur.mod" << 'EOF'
[MODULE]
SATELLITES=7530;25544;27607;
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

# 3. Clear any artifacts from previous runs
rm -f "${GPREDICT_CONF_DIR}/Manhattan_Urban.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/High_Passes.mod" 2>/dev/null || true

# 4. Set gpredict.cfg baseline
cat > "${GPREDICT_CONF_DIR}/gpredict.cfg" << 'EOF'
[GLOBAL]
DEFAULT_QTH=Pittsburgh.qth

[PREDICT]
MIN_EL=5
EOF
chown ga:ga "${GPREDICT_CONF_DIR}/gpredict.cfg"

# 5. Load the TLE data so names resolve
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
if [ -d /workspace/data ]; then
    cp /workspace/data/amateur.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
    cp /workspace/data/stations.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
    chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
fi

# Record start time for verification
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
else
    # Maximize and focus the window
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== urban_canyon_high_passes task setup complete ==="