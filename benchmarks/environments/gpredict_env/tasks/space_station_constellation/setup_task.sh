#!/bin/bash
# Setup script for space_station_constellation task
# Persona: Aerospace engineer at university space engineering lab
# Sets up an incomplete SpaceStations.mod with only ISS ZARYA (25544),
# no JSC or KSC ground stations, and UTC time not configured.

echo "=== Setting up space_station_constellation task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure Pittsburgh.qth is installed (baseline)
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Remove any existing JSC or KSC QTH files
rm -f "${GPREDICT_CONF_DIR}/JSC.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/KSC.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Houston.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Kennedy.qth" 2>/dev/null || true

# Create INCOMPLETE SpaceStations.mod with only ISS ZARYA (25544)
mkdir -p "${GPREDICT_MOD_DIR}"
cat > "${GPREDICT_MOD_DIR}/SpaceStations.mod" << 'EOF'
[MODULE]
SATELLITES=25544;
QTHFILE=Pittsburgh.qth
SHOWEV=1
SHOWMAP=1
SHOWPOLARPLOT=1
SHOWSKYAT=0
PANEL=0
NAME=SpaceStations
EOF
chown ga:ga "${GPREDICT_MOD_DIR}/SpaceStations.mod"
echo "SpaceStations.mod created with only ISS ZARYA (25544) — incomplete"

# Ensure gpredict.cfg does NOT have UTC time enabled (default to local)
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    # Remove any existing utc setting to ensure non-UTC default
    sed -i '/^utc=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

# Record baseline state
echo "25544" > /tmp/spacestations_initial_satellites
echo "no_utc" > /tmp/spacestations_initial_time_setting
date +%s > /tmp/task_start_timestamp

# Ensure Amateur.mod is present
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Update default QTH in gpredict.cfg
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Load the stations.txt TLE data (contains all space station components)
if [ -f /workspace/data/stations.txt ]; then
    mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
    cp /workspace/data/stations.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
    chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"
    echo "Space station TLE data loaded from stations.txt"
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

echo "=== space_station_constellation task setup complete ==="
echo "Starting state:"
echo "  - SpaceStations.mod: contains only ISS ZARYA (25544)"
echo "  - Missing: ISS POISK (36086), NAUKA (49044), CSS TIANHE (48274), WENTIAN (53239), MENGTIAN (54216)"
echo "  - JSC/Houston ground station: missing"
echo "  - KSC ground station: missing"
echo "  - UTC time: not configured"
