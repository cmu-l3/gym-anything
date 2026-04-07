#!/bin/bash
echo "=== Setting up radar_calibration_layout_setup task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create cache directory for TLEs
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"

# Download radar.txt from CelesTrak to ensure calibration spheres exist
echo "Fetching radar calibration TLEs..."
curl -s -m 10 "https://celestrak.org/NORAD/elements/gp.php?GROUP=radar&FORMAT=tle" -o "${GPREDICT_CONF_DIR}/satdata/cache/radar.txt" || true

# Provide fallback TLEs in case of no internet
if [ ! -s "${GPREDICT_CONF_DIR}/satdata/cache/radar.txt" ]; then
    echo "Using fallback radar TLEs..."
    cat > "${GPREDICT_CONF_DIR}/satdata/cache/radar.txt" << 'EOF'
LCS 1                   
1 01314U 65034C   23300.12345678  .00000100  00000-0  10000-3 0  9997
2 01314  32.1234 123.4567 0012345 123.4567 123.4567 14.12345678123456
CALSPHERE 1             
1 00900U 64063C   23300.12345678  .00000100  00000-0  10000-3 0  9998
2 00900  90.1234 123.4567 0012345 123.4567 123.4567 14.12345678123456
CALSPHERE 2             
1 00902U 64063E   23300.12345678  .00000100  00000-0  10000-3 0  9999
2 00902  90.1234 123.4567 0012345 123.4567 123.4567 14.12345678123456
SURCAL 159              
1 01313U 65034B   23300.12345678  .00000100  00000-0  10000-3 0  9990
2 01313  32.1234 123.4567 0012345 123.4567 123.4567 14.12345678123456
EOF
fi

chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"

# Ensure Pittsburgh.qth is the only starting ground station
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi
rm -f "${GPREDICT_CONF_DIR}/Millstone_Hill.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Millstone.qth" 2>/dev/null || true

# Ensure Amateur.mod is present and Radar_Cal is absent
mkdir -p "${GPREDICT_MOD_DIR}"
if [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi
rm -f "${GPREDICT_MOD_DIR}/Radar_Cal.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/RadarCal.mod" 2>/dev/null || true

# Ensure gpredict.cfg starts with Metric units (unit=0) and Pittsburgh default
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^unit=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^\[misc\]/a unit=0' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    else
        sed -i '/^\[GLOBAL\]/a DEFAULT_QTH=Pittsburgh.qth' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Launch GPredict
echo "Launching GPredict..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid gpredict > /tmp/gpredict_task.log 2>&1 &"
sleep 5

# Wait for GPredict window
for i in {1..30}; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Gpredict" 2>/dev/null | head -1) || true
    if [ -n "$WID" ]; then
        echo "GPredict window found (WID: $WID)"
        break
    fi
    sleep 1
done

if [ -n "$WID" ]; then
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    # Dismiss any update/startup dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="