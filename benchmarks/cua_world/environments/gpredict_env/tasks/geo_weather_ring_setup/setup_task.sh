#!/bin/bash
echo "=== Setting up geo_weather_ring_setup task ==="

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

# Remove target files if they exist (clean start)
rm -f "${GPREDICT_CONF_DIR}"/*Wallops*.qth 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}"/*Darmstadt*.qth 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}"/*Melbourne*.qth 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}"/*GEO*.mod 2>/dev/null || true

# Update default QTH to Pittsburgh
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    else
        sed -i '/^\[GLOBAL\]/a DEFAULT_QTH=Pittsburgh.qth' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Inject guaranteed TLEs for the 4 GEO weather satellites into cache
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
touch "${GPREDICT_CONF_DIR}/satdata/cache/weather.txt"
cat >> "${GPREDICT_CONF_DIR}/satdata/cache/weather.txt" << 'EOF'
GOES 16
1 41866U 16071A   23108.49051494 -.00000173  00000-0  00000-0 0  9997
2 41866   0.0267 296.2235 0001099 269.8399 104.7911  1.00273796 23377
GOES 18
1 51850U 22021A   23108.50291079 -.00000216  00000-0  00000-0 0  9995
2 51850   0.0125  34.7077 0001889 264.9213  66.4255  1.00272097  4127
METEOSAT 11
1 40732U 15034A   23108.13944690  .00000057  00000-0  00000-0 0  9996
2 40732   2.3962  71.6931 0001550 186.7262 142.1009  1.00272019 28315
HIMAWARI 9
1 41816U 16064A   23108.41165684 -.00000223  00000-0  00000-0 0  9994
2 41816   0.0210 286.0694 0001292  19.5074  22.1857  1.00271034 23626
EOF
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache"

# Record task start time
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
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial_screenshot.png 2>/dev/null || true

echo "=== geo_weather_ring_setup task setup complete ==="