#!/bin/bash
echo "=== Setting up automated_gs_hardware_setup task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_RADIOS_DIR="${GPREDICT_CONF_DIR}/radios"
GPREDICT_ROTORS_DIR="${GPREDICT_CONF_DIR}/rotors"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure Pittsburgh.qth is correctly installed (baseline station)
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Remove any existing Stanford QTH
rm -f "${GPREDICT_CONF_DIR}/Stanford_GS.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Stanford.qth" 2>/dev/null || true

# Clean up radios and rotors
rm -rf "${GPREDICT_RADIOS_DIR}" 2>/dev/null || true
rm -rf "${GPREDICT_ROTORS_DIR}" 2>/dev/null || true
mkdir -p "${GPREDICT_RADIOS_DIR}"
mkdir -p "${GPREDICT_ROTORS_DIR}"
chown -R ga:ga "${GPREDICT_RADIOS_DIR}" "${GPREDICT_ROTORS_DIR}"

# Disable auto TLE updates in gpredict.cfg if present to ensure clean slate
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/AUTO_UPDATE/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

# Record baseline state for anti-gaming checks
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

echo "=== Task setup complete ==="
echo "Starting state:"
echo "  - No radios or rotators configured"
echo "  - Stanford GS missing"
echo "  - TLE Auto updates disabled"