#!/bin/bash
# Setup script for amateur_module_reorganization task
# Persona: DX amateur radio club station manager
# Sets up two incomplete specialty modules and no remote QTH:
#   - Linear.mod with only AO-7 (7530) — needs FO-29 (24278) and AO-73 (39444)
#   - FM_Voice.mod with only AO-27 (22825) — needs SO-50 (27607), AO-85 (40967), AO-95 (43770)
#   - No Remote_RX.qth

echo "=== Setting up amateur_module_reorganization task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure Pittsburgh.qth is correctly installed
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Remove any existing Remote_RX or NJ QTH files
rm -f "${GPREDICT_CONF_DIR}/Remote_RX.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/RemoteRX.qth" 2>/dev/null || true

# Create INCOMPLETE Linear.mod with only AO-7 (NORAD 7530)
mkdir -p "${GPREDICT_MOD_DIR}"
cat > "${GPREDICT_MOD_DIR}/Linear.mod" << 'EOF'
[MODULE]
SATELLITES=7530;
QTHFILE=Pittsburgh.qth
SHOWEV=1
SHOWMAP=1
SHOWPOLARPLOT=1
SHOWSKYAT=0
PANEL=0
NAME=Linear
EOF
chown ga:ga "${GPREDICT_MOD_DIR}/Linear.mod"
echo "Linear.mod created with only AO-7 (7530) — incomplete"

# Create INCOMPLETE FM_Voice.mod with only AO-27 (NORAD 22825)
cat > "${GPREDICT_MOD_DIR}/FM_Voice.mod" << 'EOF'
[MODULE]
SATELLITES=22825;
QTHFILE=Pittsburgh.qth
SHOWEV=1
SHOWMAP=1
SHOWPOLARPLOT=1
SHOWSKYAT=0
PANEL=0
NAME=FM_Voice
EOF
chown ga:ga "${GPREDICT_MOD_DIR}/FM_Voice.mod"
echo "FM_Voice.mod created with only AO-27 (22825) — incomplete"

# Remove the generic Amateur.mod so agent focuses on the two specialty modules
# (optional: can keep it as context; removing reduces confusion about which to edit)
# Keep Amateur.mod so the env feels real
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Record baseline state
echo "7530" > /tmp/amateur_linear_initial_sats
echo "22825" > /tmp/amateur_fmvoice_initial_sats
date +%s > /tmp/task_start_timestamp

# Update default QTH in gpredict.cfg
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

echo "=== amateur_module_reorganization task setup complete ==="
echo "Starting state:"
echo "  - Linear.mod: contains only AO-7 (7530)"
echo "  - FM_Voice.mod: contains only AO-27 (22825)"
echo "  - Remote_RX.qth: missing"
