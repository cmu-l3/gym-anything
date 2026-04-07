#!/bin/bash
# Setup script for a_train_constellation_tracking task
# Persona: NASA Goddard Climate Data Scientist
# Sets up default GPredict with only the Amateur module.
# The agent must delete it, create A_Train.mod, GSFC_Goddard.qth, and enable ground tracks.

echo "=== Setting up a_train_constellation_tracking task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure Pittsburgh.qth is correctly installed (baseline station)
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Clean up any potential previous task artifacts
rm -f "${GPREDICT_CONF_DIR}/GSFC_Goddard.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Goddard.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/A_Train.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/ATrain.mod" 2>/dev/null || true

# Recreate the default Amateur.mod to ensure it exists for the agent to delete
mkdir -p "${GPREDICT_MOD_DIR}"
cat > "${GPREDICT_MOD_DIR}/Amateur.mod" << 'EOF'
[MODULE]
SATELLITES=7530;14129;14781;20442;22825;22826;23439;24278;25397;25544;26931;27607;27844;27848;27939;28895;32785;32791;32953;33499;35932;35933;35935;36122;37224;37839;37841;39090;39417;39430;39440;39444;39446;40012;40021;40025;40908;40967;41847;43017;43678;43700;43770;
QTHFILE=Pittsburgh.qth
SHOWEV=1
SHOWMAP=1
SHOWPOLARPLOT=1
SHOWSKYAT=0
PANEL=0
NAME=Amateur
EOF
chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"

# Load the TLE data needed for the constellation
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
if [ -f /workspace/data/weather.txt ]; then
    cp /workspace/data/weather.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
fi
if [ -f /workspace/data/amateur.txt ]; then
    cp /workspace/data/amateur.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
fi
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"

# Ensure default QTH is Pittsburgh and reset ground track settings in config
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    # Make sure ground tracks are turned OFF initially globally
    sed -i '/TRACK_VISIBLE/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/TRACK_ENABLE/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/show_track/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

# Record baseline state and timestamp
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
    # Maximize and focus
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -a 'Gpredict'" 2>/dev/null || true
    sleep 1
    # Dismiss any popups
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial_screenshot.png 2>/dev/null || true

echo "=== a_train_constellation_tracking task setup complete ==="
echo "Starting state:"
echo "  - Amateur.mod: Present (Must be deleted)"
echo "  - GSFC_Goddard.qth: Missing"
echo "  - A_Train.mod: Missing"
echo "  - Ground tracks: Disabled"