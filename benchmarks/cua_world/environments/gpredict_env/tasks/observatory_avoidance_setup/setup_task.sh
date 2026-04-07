#!/bin/bash
echo "=== Setting up observatory_avoidance_setup task ==="

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

# Clean up any potential files from previous runs
rm -f "${GPREDICT_CONF_DIR}/Lowell.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/McDonald.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Lowell_Avoidance.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/McDonald_Avoidance.mod" 2>/dev/null || true

# 1. Create the obsolete OldTracker module that needs to be deleted
mkdir -p "${GPREDICT_MOD_DIR}"
cat > "${GPREDICT_MOD_DIR}/OldTracker.mod" << 'EOF'
[MODULE]
SATELLITES=25544;
QTHFILE=Pittsburgh.qth
SHOWEV=1
SHOWMAP=1
SHOWPOLARPLOT=1
SHOWSKYAT=0
PANEL=0
NAME=OldTracker
EOF
chown ga:ga "${GPREDICT_MOD_DIR}/OldTracker.mod"

# 2. Ensure Amateur.mod exists and back it up to ensure it is not modified
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi
cp "${GPREDICT_MOD_DIR}/Amateur.mod" /tmp/amateur_mod_backup.txt

# 3. Ensure UTC time is NOT enabled
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    # Reset time format to local (0 = local, 1 = UTC)
    sed -i 's/^TIME_FORMAT=.*/TIME_FORMAT=0/' "${GPREDICT_CONF_DIR}/gpredict.cfg" 2>/dev/null || true
    # Also remove any utc= keys
    sed -i '/^utc=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg" 2>/dev/null || true
fi

# 4. Load all TLE data to ensure satellites are findable by name
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
for tledata in amateur.txt weather.txt stations.txt; do
    if [ -f "/workspace/data/$tledata" ]; then
        cp "/workspace/data/$tledata" "${GPREDICT_CONF_DIR}/satdata/cache/"
    fi
done
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true

# Record task start time (anti-gaming check)
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
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="