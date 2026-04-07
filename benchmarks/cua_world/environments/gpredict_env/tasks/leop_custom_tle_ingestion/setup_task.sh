#!/bin/bash
# Setup script for leop_custom_tle_ingestion task
# Sets up a local HTTP server hosting a custom TLE file and prepares a clean GPredict state.

echo "=== Setting up leop_custom_tle_ingestion task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# 1. Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# 2. Host the custom TLE file via a local python HTTP server
echo "Setting up local TLE server..."
mkdir -p /tmp/tle_server

# We use a structurally valid TLE for a real object (NORAD 47438) so it passes GPredict checksums.
cat > /tmp/tle_server/techsat.txt << 'EOF'
TECHSAT-1
1 47438U 21006E   22325.54131234  .00008064  00000-0  48226-3 0  9997
2 47438  97.4851 161.4646 0013854 186.2730 173.8368 15.11202725102574
EOF
chown -R ga:ga /tmp/tle_server

# Stop any old server and start a new one
pkill -f "python3 -m http.server 8080" || true
su - ga -c "cd /tmp/tle_server && python3 -m http.server 8080 > /tmp/tle_server.log 2>&1 &"
sleep 2

# 3. Clean GPredict's state of task-specific artifacts
# Remove any previously fetched data for 47438
rm -f "${GPREDICT_CONF_DIR}/satdata/47438.sat" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/satdata/47438.tle" 2>/dev/null || true

# Remove Ottawa ground station
rm -f "${GPREDICT_CONF_DIR}/Ottawa_Lab.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/ottawa_lab.qth" 2>/dev/null || true

# Remove LEOP module
rm -f "${GPREDICT_MOD_DIR}/LEOP_Tracking.mod" 2>/dev/null || true

# Ensure custom URL is not already in the config
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '|http://localhost:8080/techsat.txt|d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

# Ensure default Amateur module is present so GPredict has a baseline
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    mkdir -p "${GPREDICT_MOD_DIR}"
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Set baseline timestamp
date +%s > /tmp/task_start_timestamp

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
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Capture initial state
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== leop_custom_tle_ingestion task setup complete ==="