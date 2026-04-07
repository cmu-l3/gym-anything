#!/bin/bash
echo "=== Setting up iuu_dark_vessel_tracking task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure the required directories exist
mkdir -p "${GPREDICT_MOD_DIR}"
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"

# Inject TLEs for Sentinel and Landsat into a known cached file (weather.txt)
# This guarantees they appear in the GPredict search interface without needing network access
cat >> /workspace/data/weather.txt << 'EOF'
SENTINEL-1A
1 39634U 14016A   23284.12345678  .00000123  00000-0  12345-4 0  9999
2 39634  98.1818 123.4567 0001234  90.1234 270.5678 14.59123456123456
SENTINEL-2A
1 40697U 15028A   23284.12345678  .00000123  00000-0  12345-4 0  9999
2 40697  98.5621 123.4567 0001234  90.1234 270.5678 14.30823456123456
SENTINEL-2B
1 42028U 17013A   23284.12345678  .00000123  00000-0  12345-4 0  9999
2 42028  98.5621 123.4567 0001234  90.1234 270.5678 14.30823456123456
LANDSAT 8
1 39084U 13008A   23284.12345678  .00000123  00000-0  12345-4 0  9999
2 39084  98.2000 123.4567 0001234  90.1234 270.5678 14.57123456123456
LANDSAT 9
1 49260U 21088A   23284.12345678  .00000123  00000-0  12345-4 0  9999
2 49260  98.2000 123.4567 0001234  90.1234 270.5678 14.57123456123456
EOF

# Copy all local TLEs into GPredict's cache
cp /workspace/data/*.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"

# Reset baseline state: Remove any existing target modules and QTH files
rm -f "${GPREDICT_MOD_DIR}/Dark_Vessels.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/Dark Vessels.mod" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Galapagos_Reserve.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Galapagos Reserve.qth" 2>/dev/null || true

# Provide default Pittsburgh ground station
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Reset map preferences to default (no shadow, lon=0)
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/shadow=/Id' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/center_lon=/Id' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/lon=/Id' "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Launch GPredict
echo "Launching GPredict..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid gpredict > /tmp/gpredict_task.log 2>&1 &"
sleep 5

# Wait for GPredict window
for i in {1..15}; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Gpredict" 2>/dev/null | head -1) || true
    if [ -n "$WID" ]; then
        echo "GPredict window found (WID: $WID)"
        # Maximize window
        su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r $WID -b add,maximized_vert,maximized_horz" 2>/dev/null || true
        # Focus window
        su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -a $WID" 2>/dev/null || true
        break
    fi
    sleep 2
done

# Dismiss any startup dialogs
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="