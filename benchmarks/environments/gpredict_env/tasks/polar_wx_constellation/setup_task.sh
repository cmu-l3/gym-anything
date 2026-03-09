#!/bin/bash
# Setup script for polar_wx_constellation task
# Persona: NOAA/NWS satellite meteorologist
# Sets up a misconfigured GPredict installation:
#   - PolarWX.mod containing ISS (25544) instead of weather satellites
#   - No Alaska ground stations
#   - Metric units NOT enabled

echo "=== Setting up polar_wx_constellation task ==="

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

# Remove any existing Alaska ground stations (clean start)
rm -f "${GPREDICT_CONF_DIR}/Fairbanks.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Anchorage.qth" 2>/dev/null || true

# Create MISCONFIGURED PolarWX.mod with ISS (not weather satellites)
# The agent must detect that ISS doesn't belong and fix the module
mkdir -p "${GPREDICT_MOD_DIR}"
cat > "${GPREDICT_MOD_DIR}/PolarWX.mod" << 'EOF'
[MODULE]
SATELLITES=25544;
QTHFILE=Pittsburgh.qth
SHOWEV=1
SHOWMAP=1
SHOWPOLARPLOT=1
SHOWSKYAT=0
PANEL=0
NAME=PolarWX
EOF
chown ga:ga "${GPREDICT_MOD_DIR}/PolarWX.mod"
echo "PolarWX.mod created with WRONG satellite: ISS (25544) instead of weather satellites"

# Record baseline state
echo "25544" > /tmp/polarwx_initial_satellites
echo "0" > /tmp/polarwx_initial_metric_setting
date +%s > /tmp/task_start_timestamp

# Ensure Amateur.mod is present
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Ensure gpredict.cfg exists and does NOT have metric units enabled
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    # Remove any existing metric unit setting to ensure default (imperial/miles)
    sed -i '/^unit=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

# Update default QTH
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

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

echo "=== polar_wx_constellation task setup complete ==="
echo "Starting state:"
echo "  - PolarWX.mod: contains only ISS (25544) - WRONG, needs weather satellites"
echo "  - Required: SUOMI NPP (37849), FENGYUN 3A (32958), FENGYUN 3B (37214), DMSP F18 (35951)"
echo "  - Fairbanks.qth: missing"
echo "  - Anchorage.qth: missing"
echo "  - Metric units: NOT configured"
