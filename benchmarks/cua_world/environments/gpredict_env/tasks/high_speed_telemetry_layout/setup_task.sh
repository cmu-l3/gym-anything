#!/bin/bash
echo "=== Setting up high_speed_telemetry_layout task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Kill any existing GPredict instance for clean setup
pkill -x gpredict || true
sleep 2

# Ensure baseline configuration exists
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Pre-load weather TLE data so satellites are easily searchable
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
if [ -f /workspace/data/weather.txt ]; then
    cp /workspace/data/weather.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
    chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"
    echo "Weather TLE data pre-loaded."
fi

# Remove target files if they exist to prevent gaming
rm -f "${GPREDICT_CONF_DIR}/Tromso.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/tromso.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Physics_Telemetry.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/PhysicsTelemetry.mod" 2>/dev/null || true

# Reset update cycle and default QTH to baseline in gpredict.cfg
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^CYCLE=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Ensure default Amateur module exists so app isn't empty
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    mkdir -p "${GPREDICT_MOD_DIR}"
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
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
    # Maximize and focus the window
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    # Dismiss any update/startup dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="