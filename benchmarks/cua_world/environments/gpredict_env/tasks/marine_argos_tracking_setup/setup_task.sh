#!/bin/bash
echo "=== Setting up marine_argos_tracking_setup task ==="

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

# Remove any target QTH files (clean start)
rm -f "${GPREDICT_CONF_DIR}/Galapagos_Base.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Galapagos.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Ascension_Island.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Ascension.qth" 2>/dev/null || true

# Remove Argos_Tracking module if it exists
rm -f "${GPREDICT_MOD_DIR}/Argos_Tracking.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Argos.mod" 2>/dev/null || true

# Ensure Amateur.mod is present (agent must delete it)
mkdir -p "${GPREDICT_MOD_DIR}"
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# If it's still missing, create a dummy one
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
cat > "${GPREDICT_MOD_DIR}/Amateur.mod" << 'EOF'
[MODULE]
SATELLITES=25544;
QTHFILE=Pittsburgh.qth
SHOWEV=1
SHOWMAP=1
SHOWPOLARPLOT=1
SHOWSKYAT=0
PANEL=0
NAME=Amateur
EOF
chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Ensure gpredict.cfg does NOT have metric units enabled
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    # Remove any existing metric unit setting to ensure default (imperial/miles)
    sed -i '/^unit=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    # Ensure default QTH is Pittsburgh
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Load TLE data (contains NOAAs and METOPs)
if [ -f /workspace/data/weather.txt ]; then
    mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
    cp /workspace/data/weather.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
    chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"
fi

# Record baseline state
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
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== marine_argos_tracking_setup task setup complete ==="