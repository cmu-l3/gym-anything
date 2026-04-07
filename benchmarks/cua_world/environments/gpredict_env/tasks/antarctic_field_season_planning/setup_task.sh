#!/bin/bash
# Setup script for antarctic_field_season_planning task
# Persona: Antarctic Field Researcher
# Sets up default GPredict (Pittsburgh) and clears any Antarctic configurations.
# Ensures TLE data for required satellites is loaded into the cache.

echo "=== Setting up antarctic_field_season_planning task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Clean up existing files that the agent is supposed to create
rm -f "${GPREDICT_CONF_DIR}/Palmer_Station.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Palmer.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Punta_Arenas.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/PuntaArenas.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/PalmerComms.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/PalmerWX.mod" 2>/dev/null || true

# Ensure Pittsburgh.qth is correctly installed (baseline)
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Ensure Amateur.mod is present
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    mkdir -p "${GPREDICT_MOD_DIR}"
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Set default QTH to Pittsburgh (ensures agent must change it)
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    else
        sed -i '/^\[GLOBAL\]/a DEFAULT_QTH=Pittsburgh.qth' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Load TLE data caches so agent can search satellites by name
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
for tle_file in amateur.txt weather.txt stations.txt; do
    if [ -f "/workspace/data/$tle_file" ]; then
        cp "/workspace/data/$tle_file" "${GPREDICT_CONF_DIR}/satdata/cache/"
    fi
done
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
echo "TLE caches pre-loaded with required data."

# Record start time for anti-gaming verification
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
    # Maximize window
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    # Dismiss any welcome dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
else
    echo "WARNING: GPredict window not found after ${TIMEOUT}s"
    cat /tmp/gpredict_task.log 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== antarctic_field_season_planning task setup complete ==="
echo "Starting state: Default configuration (Pittsburgh ground station, no Antarctic stations or modules)."