#!/bin/bash
# Setup script for gnss_timing_calibration_setup task
# Persona: Metrologist at NIST Time Laboratory
# Starts with a clean state, explicitly deleting any GNSS data so the agent MUST download it.

echo "=== Setting up gnss_timing_calibration_setup task ==="

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

# 1. Cleanup any pre-existing GNSS tracking modules or ground stations
rm -f "${GPREDICT_CONF_DIR}/NIST_Boulder.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/NIST.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/GNSS_Timing.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/GNSS.mod" 2>/dev/null || true

# 2. REMOVE GNSS satellites from satdata cache
# This forces the agent to actually perform the Network TLE Update to get them.
rm -f "${GPREDICT_CONF_DIR}/satdata/55268.sat" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/satdata/48859.sat" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/satdata/43058.sat" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/satdata/43565.sat" 2>/dev/null || true

# 3. Strip existing GNSS URLs or UTC configs from gpredict.cfg
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    # Remove gnss.txt feed if present
    sed -i '/gnss\.txt/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    
    # Ensure local time is used (UTC is OFF)
    sed -i '/TIME_LOCAL=false/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/utc=1/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    if ! grep -q "TIME_LOCAL=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i '/^\[GLOBAL\]/a TIME_LOCAL=true' "${GPREDICT_CONF_DIR}/gpredict.cfg" || echo "TIME_LOCAL=true" >> "${GPREDICT_CONF_DIR}/gpredict.cfg"
    else
        sed -i 's/^TIME_LOCAL=.*/TIME_LOCAL=true/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
    
    # Ensure Default QTH is Pittsburgh
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Ensure Amateur.mod is present so it's not totally empty
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    mkdir -p "${GPREDICT_MOD_DIR}"
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
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

if [ -n "$WID" ]; then
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    # Dismiss any update dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== gnss_timing_calibration_setup task setup complete ==="
echo "Starting state:"
echo "  - gnss.txt feed missing from config"
echo "  - GNSS satellite data absent from cache (forces network update)"
echo "  - NIST_Boulder.qth missing"
echo "  - GNSS_Timing.mod missing"
echo "  - Local time enforced"