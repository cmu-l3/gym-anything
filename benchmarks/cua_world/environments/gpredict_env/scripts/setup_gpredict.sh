#!/bin/bash
set -e

echo "=== Setting up GPredict ==="

# Wait for desktop to be ready
sleep 5

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_SAT_DIR="${GPREDICT_CONF_DIR}/satdata"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Do NOT pre-create GPredict config directories — let GPredict's first-time
# initialization handle them. Pre-creating directories causes first-time init
# to skip copying Amateur.mod and other essential default files.

# Warm-up launch: start GPredict to trigger first-time initialization,
# then close it to get a clean baseline config
echo "Performing warm-up launch to initialize GPredict..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid gpredict > /tmp/gpredict_warmup.log 2>&1 &"
sleep 10

# Check if GPredict window appeared
WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Gpredict" 2>/dev/null | head -1) || true
if [ -n "$WID" ]; then
    echo "GPredict window found (WID: $WID), dismissing any dialogs..."
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --window "$WID" Escape 2>/dev/null || true
    sleep 1
fi

# Kill the warm-up instance (use -x for exact process name match;
# -f would match THIS script's name "setup_gpredict.sh" and kill ourselves)
pkill -x gpredict || true
sleep 2

# Verify first-time initialization completed
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    echo "GPredict configuration initialized successfully."
else
    echo "WARNING: gpredict.cfg not found after warm-up."
fi

# Ensure Amateur.mod is present (fallback if first-time init missed it)
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    echo "Amateur.mod missing, copying from system defaults..."
    mkdir -p "${GPREDICT_MOD_DIR}"
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Set Pittsburgh, PA as the default ground station.
# GPredict displays the filename (minus .qth) as the station name in the UI,
# so we copy as Pittsburgh.qth and update gpredict.cfg to point to it.
echo "Setting up Pittsburgh ground station as default..."
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    # Remove the default sample.qth so only Pittsburgh exists
    rm -f "${GPREDICT_CONF_DIR}/sample.qth"
    # Update gpredict.cfg to use Pittsburgh.qth as the default ground station
    if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
        if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
            sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
        else
            # Add DEFAULT_QTH under [GLOBAL] section
            sed -i '/^\[GLOBAL\]/a DEFAULT_QTH=Pittsburgh.qth' "${GPREDICT_CONF_DIR}/gpredict.cfg"
        fi
    fi
fi

# Copy real TLE data from CelesTrak into satdata cache for TLE updates
echo "Loading real satellite TLE data from CelesTrak..."
if [ -d /workspace/data ]; then
    mkdir -p "${GPREDICT_SAT_DIR}/cache"
    cp /workspace/data/stations.txt "${GPREDICT_SAT_DIR}/cache/" 2>/dev/null || true
    cp /workspace/data/amateur.txt "${GPREDICT_SAT_DIR}/cache/" 2>/dev/null || true
    cp /workspace/data/weather.txt "${GPREDICT_SAT_DIR}/cache/" 2>/dev/null || true
    chown -R ga:ga "${GPREDICT_SAT_DIR}/cache/"
fi

echo "=== GPredict setup complete ==="
