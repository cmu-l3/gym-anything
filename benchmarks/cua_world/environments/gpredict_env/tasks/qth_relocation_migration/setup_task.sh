#!/bin/bash
# Setup script for qth_relocation_migration task
# Persona: Amateur radio operator relocating from Pittsburgh to Denver
# Sets up a configuration heavily tied to Pittsburgh.

echo "=== Setting up qth_relocation_migration task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

mkdir -p "${GPREDICT_MOD_DIR}"
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"

# Ensure all needed TLE data is cached so the agent can find satellites by name
if [ -d /workspace/data ]; then
    cp /workspace/data/amateur.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
    cp /workspace/data/weather.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
    cp /workspace/data/stations.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
fi

# Clean up any leftover Denver config from previous runs
rm -f "${GPREDICT_CONF_DIR}/Denver"* 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Denver"* 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/denver"* 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/denver"* 2>/dev/null || true

# 1. Create Pittsburgh.qth
cat > "${GPREDICT_CONF_DIR}/Pittsburgh.qth" << 'EOF'
[GROUND STATION]
LOCATION=Pittsburgh, PA
LAT=40.4406
LON=-79.9959
ALT=230
WX=KPIT
EOF
chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"

# 2. Create the legacy Amateur.mod (which the user must delete)
cat > "${GPREDICT_MOD_DIR}/Amateur.mod" << 'EOF'
[MODULE]
SATELLITES=7530;27607;
QTHFILE=Pittsburgh.qth
SHOWEV=1
SHOWMAP=1
SHOWPOLARPLOT=1
SHOWSKYAT=0
PANEL=0
NAME=Amateur
EOF
chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"

# 3. Update gpredict.cfg with Pittsburgh default and NO UTC
if [ ! -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    echo "[GLOBAL]" > "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi
# Remove existing default QTH and UTC settings
sed -i '/^DEFAULT_QTH=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
sed -i '/^utc=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
# Add Pittsburgh as default
sed -i '/^\[GLOBAL\]/a DEFAULT_QTH=Pittsburgh.qth' "${GPREDICT_CONF_DIR}/gpredict.cfg"
chown ga:ga "${GPREDICT_CONF_DIR}/gpredict.cfg"

# Fix permissions
chown -R ga:ga "${GPREDICT_CONF_DIR}"

# Record timestamps
date +%s > /tmp/task_start_time.txt
echo "setup_complete" > /tmp/task_setup_status.txt

# 4. Launch GPredict
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
    # Dismiss any startup tips
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task Setup Complete ==="
echo "Starting state established: Pittsburgh default, Amateur.mod present, local time enabled."