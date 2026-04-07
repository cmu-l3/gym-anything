#!/bin/bash
# Setup script for noaa_apt_reception_setup task
# Persona: Weather Enthusiast / Amateur Radio Operator
# Prepares a clean GPredict environment needing NOAA APT setup.

echo "=== Setting up noaa_apt_reception_setup task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"
GPREDICT_TRSP_DIR="${GPREDICT_CONF_DIR}/trsp"

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure Amateur.mod is present (baseline)
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    mkdir -p "${GPREDICT_MOD_DIR}"
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Ensure Pittsburgh.qth is correctly installed (baseline)
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# 1. Clean slate: Remove existing Wallops.qth
rm -f "${GPREDICT_CONF_DIR}/Wallops.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/wallops.qth" 2>/dev/null || true

# 2. Clean slate: Remove existing NOAA_APT.mod
rm -f "${GPREDICT_MOD_DIR}/NOAA_APT.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/noaa_apt.mod" 2>/dev/null || true

# 3. Clean slate: Ensure trsp directory exists and remove existing NOAA transponders
mkdir -p "${GPREDICT_TRSP_DIR}"
rm -f "${GPREDICT_TRSP_DIR}/25338.trsp" 2>/dev/null || true
rm -f "${GPREDICT_TRSP_DIR}/28654.trsp" 2>/dev/null || true
rm -f "${GPREDICT_TRSP_DIR}/33591.trsp" 2>/dev/null || true
chown -R ga:ga "${GPREDICT_TRSP_DIR}"

# Ensure weather TLEs are loaded so GPredict can search NOAA satellites
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
if [ -f /workspace/data/weather.txt ]; then
    cp /workspace/data/weather.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
fi
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true

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
    # Maximize and focus
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -a 'Gpredict'" 2>/dev/null || true
    sleep 1
    # Dismiss any update dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="