#!/bin/bash
# Setup script for research_vessel_expedition task
echo "=== Setting up research_vessel_expedition task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Kill any existing GPredict instances
pkill -x gpredict || true
sleep 2

# Ensure baseline Pittsburgh.qth and Amateur.mod are present
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    mkdir -p "${GPREDICT_MOD_DIR}"
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Load TLE data cache so satellites can be found by name
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
for tle in amateur.txt weather.txt stations.txt; do
    if [ -f "/workspace/data/$tle" ]; then
        cp "/workspace/data/$tle" "${GPREDICT_CONF_DIR}/satdata/cache/"
    fi
done
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true

# Remove any existing target files from previous attempts
rm -f "${GPREDICT_CONF_DIR}/Woods_Hole.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/MidAtlantic.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/WX_Reception.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/SatComm.mod" 2>/dev/null || true

# Create the stale "PreviousCruise.qth"
cat > "${GPREDICT_CONF_DIR}/PreviousCruise.qth" << 'EOF'
[GROUND STATION]
NAME=PreviousCruise
LOCATION=Caribbean
LAT=18.450000
LON=-66.105700
ALT=5
WX=
GPSD_SERVER=localhost
GPSD_PORT=2947
EOF
chown ga:ga "${GPREDICT_CONF_DIR}/PreviousCruise.qth"
echo "Stale PreviousCruise.qth injected."

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
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
fi

# Take initial screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup complete ==="