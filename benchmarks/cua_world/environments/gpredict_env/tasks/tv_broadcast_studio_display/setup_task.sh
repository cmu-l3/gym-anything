#!/bin/bash
# Setup script for tv_broadcast_studio_display task

echo "=== Setting up tv_broadcast_studio_display task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure Amateur.mod is present (so the agent has something to delete)
mkdir -p "${GPREDICT_MOD_DIR}"
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Ensure Pittsburgh.qth is installed (baseline station)
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Remove any New York / Studio QTH and Modules (clean start)
rm -f "${GPREDICT_CONF_DIR}/New_York_Studio.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/New_York.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Studio_Map.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Studio Map.mod" 2>/dev/null || true

# Pre-load all necessary TLE data into cache so HST (20580) and ISS (25544) are available
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
for f in /workspace/data/*.txt; do
    if [ -f "$f" ]; then
        cp "$f" "${GPREDICT_CONF_DIR}/satdata/cache/"
    fi
done
# If active.txt, visual.txt or stations.txt exist, HST and ISS will be there.
# CelesTrak active.txt contains both. Let's make sure it's available or we just load everything.
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true

# Force incorrect map preferences (Agent must fix them)
# GRID=true, SUN=true, MOON=true, SHADOW=false
CFG_FILE="${GPREDICT_CONF_DIR}/gpredict.cfg"
if [ ! -f "$CFG_FILE" ]; then
    touch "$CFG_FILE"
fi

# Remove existing Map-View lines to avoid duplicates
sed -i '/^GRID=/d' "$CFG_FILE"
sed -i '/^SUN=/d' "$CFG_FILE"
sed -i '/^MOON=/d' "$CFG_FILE"
sed -i '/^SHADOW=/d' "$CFG_FILE"

# Add [Map-View] section if it doesn't exist, then inject wrong settings
if ! grep -q "^\[Map-View\]" "$CFG_FILE"; then
    echo "[Map-View]" >> "$CFG_FILE"
fi
sed -i '/^\[Map-View\]/a GRID=true\nSUN=true\nMOON=true\nSHADOW=false' "$CFG_FILE"
chown ga:ga "$CFG_FILE"

# Update default QTH
if grep -q "^DEFAULT_QTH=" "$CFG_FILE"; then
    sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "$CFG_FILE"
else
    echo "DEFAULT_QTH=Pittsburgh.qth" >> "$CFG_FILE"
fi

# Record baseline state
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
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== tv_broadcast_studio_display task setup complete ==="