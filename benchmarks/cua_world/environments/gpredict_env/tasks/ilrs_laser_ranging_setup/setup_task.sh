#!/bin/bash
echo "=== Setting up ILRS Laser Ranging task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure baseline QTH is present
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Remove target files if they somehow exist (clean start)
rm -f "${GPREDICT_CONF_DIR}/Matera_SLR.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Yarragadee_SLR.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/ILRS_Targets.mod" 2>/dev/null || true

# Inject ILRS satellite TLEs into the amateur.txt cache so they are 
# easily searchable in the GPredict UI by name or ID.
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
if [ -f /workspace/data/amateur.txt ]; then
    cp /workspace/data/amateur.txt "${GPREDICT_CONF_DIR}/satdata/cache/amateur.txt"
fi

# Append Geodetic SLR targets to guarantee UI visibility
cat >> "${GPREDICT_CONF_DIR}/satdata/cache/amateur.txt" << 'EOF'
LAGEOS 1
1 08820U 76039A   24001.12345678  .00000000  00000-0  00000-0 0  9999
2 08820 109.8330 123.4560 0045600   0.0000   0.0000  6.38660000000000
LAGEOS 2
1 22195U 92070B   24001.12345678  .00000000  00000-0  00000-0 0  9999
2 22195  52.6400 123.4560 0135000   0.0000   0.0000  6.47200000000000
STARLETTE
1 07646U 75010A   24001.12345678  .00000000  00000-0  00000-0 0  9999
2 07646  49.8300 123.4560 0206000   0.0000   0.0000 13.82300000000000
STELLA
1 22823U 93061B   24001.12345678  .00000000  00000-0  00000-0 0  9999
2 22823  98.6800 123.4560 0012000   0.0000   0.0000 14.30000000000000
LARES
1 38077U 12006A   24001.12345678  .00000000  00000-0  00000-0 0  9999
2 38077  69.4900 123.4560 0000000   0.0000   0.0000 12.50000000000000
EOF
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache"

# Reset configuration parameters so the agent has to explicitly set them
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    # Ensure minimum elevation is default (0) and units are default (imperial/miles)
    sed -i '/^MIN_EL=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^unit=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    
    # Set default QTH
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    else
        sed -i '/^\[GLOBAL\]/a DEFAULT_QTH=Pittsburgh.qth' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Record start time for anti-gaming checks
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
    # Dismiss any startup tips dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup complete ==="