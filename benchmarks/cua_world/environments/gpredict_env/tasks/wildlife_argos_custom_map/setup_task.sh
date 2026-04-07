#!/bin/bash
echo "=== Setting up wildlife_argos_custom_map task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Create the custom map assets in /workspace/data/
mkdir -p /workspace/data
# Generate a dummy bathymetry map image if it doesn't exist (deep sky blue color)
if [ ! -f /workspace/data/ocean_bathymetry.png ]; then
    convert -size 2048x1024 xc:deepskyblue /workspace/data/ocean_bathymetry.png 2>/dev/null || true
fi

# Create the map info file
cat > /workspace/data/ocean_bathymetry.info << 'EOF'
[map]
name=Ocean Bathymetry
file=ocean_bathymetry.png
EOF
chown -R ga:ga /workspace/data/ocean_bathymetry.* 2>/dev/null || true

# Ensure clean state (remove any previous agent work)
rm -rf "${GPREDICT_CONF_DIR}/maps"
rm -f "${GPREDICT_CONF_DIR}/Galapagos_CDRS.qth"
rm -f "${GPREDICT_CONF_DIR}/galapagos_cdrs.qth"
rm -f "${GPREDICT_CONF_DIR}/modules/Argos_Network.mod"

# Ensure gpredict.cfg is in default state
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    # Remove custom map and grid settings
    sed -i '/^MAP=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^DRAW_GRID=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    # Ensure default station is Pittsburgh
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

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
    # Maximize window
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    # Dismiss any dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="