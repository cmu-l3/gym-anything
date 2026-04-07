#!/bin/bash
# Setup script for export_stargazing_passes task
# Sets up a clean default GPredict installation:
#   - Removes any existing Cherry_Springs QTH
#   - Removes any existing exported text files
#   - Resets MIN_EL in preferences

echo "=== Setting up export_stargazing_passes task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
DOCUMENTS_DIR="/home/ga/Documents"

# Ensure Documents directory exists
mkdir -p "$DOCUMENTS_DIR"
chown ga:ga "$DOCUMENTS_DIR"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Remove target artifact files to ensure a clean slate
rm -f "${DOCUMENTS_DIR}/ISS_passes.txt" 2>/dev/null || true
rm -f "${DOCUMENTS_DIR}/CSS_passes.txt" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Cherry_Springs.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/CherrySprings.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/cherry_springs.qth" 2>/dev/null || true

# Clean up gpredict.cfg to default state (removing existing MIN_EL settings)
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"
if [ -f "$GPREDICT_CFG" ]; then
    sed -i '/^MIN_EL=/d' "$GPREDICT_CFG"
fi

# Ensure Amateur.mod is present (required for target discovery if agent doesn't use search)
if [ ! -f "${GPREDICT_CONF_DIR}/modules/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    mkdir -p "${GPREDICT_CONF_DIR}/modules"
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_CONF_DIR}/modules/Amateur.mod"
    chown ga:ga "${GPREDICT_CONF_DIR}/modules/Amateur.mod"
fi

# Load complete TLEs so ISS and CSS are immediately available in searches
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
for f in amateur.txt stations.txt weather.txt; do
    if [ -f "/workspace/data/$f" ]; then
        cp "/workspace/data/$f" "${GPREDICT_CONF_DIR}/satdata/cache/"
    fi
done
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache" 2>/dev/null || true

# Record the start time of the task (anti-gaming)
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

if [ -z "$WID" ]; then
    echo "WARNING: GPredict window not found after ${TIMEOUT}s"
    cat /tmp/gpredict_task.log 2>/dev/null || true
else
    # Maximize window
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    # Dismiss any update/first-run dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot to prove starting state
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== export_stargazing_passes task setup complete ==="