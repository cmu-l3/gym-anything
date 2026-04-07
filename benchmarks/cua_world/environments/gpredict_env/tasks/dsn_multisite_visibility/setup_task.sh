#!/bin/bash
# Setup script for dsn_multisite_visibility task
# Persona: Aerospace engineering instructor
# Sets up a clean baseline with only Pittsburgh.qth and Amateur.mod.
# Removes any existing DSN modules or ground stations.

echo "=== Setting up dsn_multisite_visibility task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure Pittsburgh.qth is correctly installed (baseline default)
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Clean up any previous runs
rm -f "${GPREDICT_CONF_DIR}"/*oldstone*.qth 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}"/*adrid*.qth 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}"/*anberra*.qth 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}"/*DSN*.mod 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}"/*oldstone*.mod 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}"/*adrid*.mod 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}"/*anberra*.mod 2>/dev/null || true

# Ensure gpredict.cfg does NOT have UTC enabled by default
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^utc=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^use_local_time=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

# Ensure TLE data is populated so agent can search for satellites
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
for f in stations.txt weather.txt amateur.txt; do
    if [ -f "/workspace/data/$f" ]; then
        cp "/workspace/data/$f" "${GPREDICT_CONF_DIR}/satdata/cache/"
    fi
done
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true

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

if [ -n "$WID" ]; then
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    # Dismiss any startup tips or errors
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== dsn_multisite_visibility task setup complete ==="