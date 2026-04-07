#!/bin/bash
# Setup script for ag_drought_monitoring_setup task

echo "=== Setting up ag_drought_monitoring_setup task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure directories exist
mkdir -p "${GPREDICT_MOD_DIR}"
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"

# Load TLE data (weather satellites) into cache to ensure they are searchable
if [ -f /workspace/data/weather.txt ]; then
    cp /workspace/data/weather.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
    chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"
    echo "Weather TLE data loaded."
fi

# Ensure Pittsburgh.qth is correctly installed (baseline station)
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Create the obsolete ground station that needs to be deleted
cat > "${GPREDICT_CONF_DIR}/Old_HQ.qth" << 'EOF'
[GROUND STATION]
LOCATION=Old_HQ
LAT=38.627000
LON=-90.199400
ALT=140
WX=KSTL
GPSD_SERVER=
GPSD_PORT=2947
EOF
chown ga:ga "${GPREDICT_CONF_DIR}/Old_HQ.qth"
echo "Obsolete ground station Old_HQ.qth created."

# Remove any existing target QTH files or modules (clean start)
rm -f "${GPREDICT_CONF_DIR}/Iowa_Test_Farm.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Nebraska_Site.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Drought_Monitor.mod" 2>/dev/null || true

# Update gpredict.cfg to ensure Pittsburgh is default, not Iowa
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    else
        sed -i '/^\[GLOBAL\]/a DEFAULT_QTH=Pittsburgh.qth' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Record start time for anti-gaming (checking if files were created during task)
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
    cat /tmp/gpredict_task.log 2>/dev/null || true
else
    # Maximize window
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    # Dismiss any initial startup dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== ag_drought_monitoring_setup task setup complete ==="
echo "Starting state:"
echo "  - Old_HQ.qth: exists (needs to be deleted)"
echo "  - Iowa_Test_Farm.qth: missing (needs to be created and set as default)"
echo "  - Nebraska_Site.qth: missing (needs to be created)"
echo "  - Drought_Monitor.mod: missing (needs to be created with 5 weather sats)"