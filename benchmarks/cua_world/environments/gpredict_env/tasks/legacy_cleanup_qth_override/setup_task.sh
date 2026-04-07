#!/bin/bash
set -e

echo "=== Setting up legacy_cleanup_qth_override task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Kill any running GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure Amateur.mod is present
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    mkdir -p "${GPREDICT_MOD_DIR}"
    if [ -f /usr/share/gpredict/data/Amateur.mod ]; then
        cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
        chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
    fi
fi

# Set Pittsburgh.qth as the default baseline
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Clean up any potential conflicting files
rm -f "${GPREDICT_CONF_DIR}/White_Sands.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/WhiteSands.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/White Sands.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Wallops_Island.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/WallopsIsland.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Wallops Island.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/LEO_Comms.mod" 2>/dev/null || true

# 1. Create the two "leftover test" modules to be deleted
mkdir -p "${GPREDICT_MOD_DIR}"

cat > "${GPREDICT_MOD_DIR}/TestModule1.mod" << 'EOF'
[MODULE]
SATELLITES=25544;
QTHFILE=Pittsburgh.qth
SHOWEV=1
SHOWMAP=1
SHOWPOLARPLOT=1
SHOWSKYAT=0
PANEL=0
NAME=TestModule1
EOF

cat > "${GPREDICT_MOD_DIR}/TestModule2.mod" << 'EOF'
[MODULE]
SATELLITES=27607;
QTHFILE=Pittsburgh.qth
SHOWEV=1
SHOWMAP=1
SHOWPOLARPLOT=1
SHOWSKYAT=0
PANEL=0
NAME=TestModule2
EOF

chown ga:ga "${GPREDICT_MOD_DIR}/TestModule1.mod"
chown ga:ga "${GPREDICT_MOD_DIR}/TestModule2.mod"
echo "Created TestModule1 and TestModule2 to be deleted by agent."

# Update gpredict.cfg to use Pittsburgh.qth as default initially
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    else
        sed -i '/^\[GLOBAL\]/a DEFAULT_QTH=Pittsburgh.qth' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Pre-load TLE data so the required satellites are searchable by name
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
if [ -f /workspace/data/amateur.txt ]; then
    cp /workspace/data/amateur.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
fi
if [ -f /workspace/data/stations.txt ]; then
    cp /workspace/data/stations.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
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

if [ -z "$WID" ]; then
    echo "WARNING: GPredict window not found after ${TIMEOUT}s"
    cat /tmp/gpredict_task.log 2>/dev/null || true
else
    # Maximize window
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    # Dismiss any dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Task setup complete ==="