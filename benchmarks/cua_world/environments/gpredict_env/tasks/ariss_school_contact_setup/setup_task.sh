#!/bin/bash
# Setup script for ariss_school_contact_setup task
# Clears out conflicting files, sets up baseline environment, records start time.

echo "=== Setting up ariss_school_contact_setup task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# 1. Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# 2. Ensure Pittsburgh.qth is correctly installed (baseline default station)
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# 3. Clean slate: remove any pre-existing files that the agent is supposed to create
rm -f "${GPREDICT_CONF_DIR}/Denver_School.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Telebridge_Italy.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}"/*Denver*.qth 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}"/*Telebridge*.qth 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/ARISS_Contact.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Other_Passes.mod" 2>/dev/null || true

# 4. Ensure Amateur.mod is present so the UI isn't completely empty initially
mkdir -p "${GPREDICT_MOD_DIR}"
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# 5. Ensure gpredict.cfg does NOT have UTC time enabled (default to local time)
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    # Remove any existing utc setting to ensure non-UTC default
    sed -i '/^utc=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    # Ensure default QTH is Pittsburgh
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# 6. Load the necessary TLE data into cache so satellites can be searched by name
if [ -d /workspace/data ]; then
    mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
    cp /workspace/data/stations.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
    cp /workspace/data/amateur.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
    chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"
    echo "Space station and amateur TLE data loaded."
fi

# 7. Record baseline state (for anti-gaming verification)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# 8. Launch GPredict
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
    # Dismiss any startup tips dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== ariss_school_contact_setup task setup complete ==="