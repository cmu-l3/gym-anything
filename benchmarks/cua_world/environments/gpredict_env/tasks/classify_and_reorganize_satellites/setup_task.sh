#!/bin/bash
# Setup script for classify_and_reorganize_satellites task (Very Hard)
# Persona: AMSAT regional coordinator inheriting misconfigured system
#
# The Amateur.mod is "contaminated" with 4 weather satellite NORAD IDs:
#   - SUOMI NPP (37849), FENGYUN 3A (32958), FENGYUN 3B (37214), DMSP F18 (35951)
# These appear among the real amateur satellites. Agent must identify and reclassify them.

echo "=== Setting up classify_and_reorganize_satellites task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure Pittsburgh.qth is installed
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Remove Fairbanks QTH (agent must add it)
rm -f "${GPREDICT_CONF_DIR}/Fairbanks.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/fairbanks.qth" 2>/dev/null || true

# Remove WeatherSats module if it exists (clean start)
rm -f "${GPREDICT_MOD_DIR}/WeatherSats.mod" 2>/dev/null || true

# Load all TLE data (both amateur and weather) so GPredict can display satellite names
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
if [ -f /workspace/data/amateur.txt ]; then
    cp /workspace/data/amateur.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
fi
if [ -f /workspace/data/weather.txt ]; then
    cp /workspace/data/weather.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
fi
if [ -f /workspace/data/stations.txt ]; then
    cp /workspace/data/stations.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
fi
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
echo "All TLE data loaded (amateur + weather + stations)"

# Create the CONTAMINATED Amateur.mod
# Contains all real amateur satellites PLUS the 4 weather satellites mixed in
mkdir -p "${GPREDICT_MOD_DIR}"

# Real amateur satellite NORAD IDs (from amateur.txt):
# 7530, 14129, 14781, 20442, 22825, 22826, 23439, 24278, 25397, 25544, 26931,
# 27607, 27844, 27848, 27939, 28895, 32785, 32791, 32953, 33499, 35932, 35933,
# 35935, 36122, 37224, 37839, 37841, 39090, 39417, 39430, 39440, 39444, 39446,
# 40012, 40021, 40025, 40908, 40967, 41847, 43017, 43678, 43700, 43770
#
# Weather satellites INJECTED (should not be here):
# 37849 (SUOMI NPP), 32958 (FENGYUN 3A), 37214 (FENGYUN 3B), 35951 (DMSP F18)

cat > "${GPREDICT_MOD_DIR}/Amateur.mod" << 'EOF'
[MODULE]
SATELLITES=7530;14129;14781;20442;22825;22826;23439;24278;25397;25544;26931;27607;27844;27848;27939;28895;32785;32791;32953;32958;33499;35932;35933;35935;35951;36122;37214;37224;37839;37841;37849;39090;39417;39430;39440;39444;39446;40012;40021;40025;40908;40967;41847;43017;43678;43700;43770;
QTHFILE=Pittsburgh.qth
SHOWEV=1
SHOWMAP=1
SHOWPOLARPLOT=1
SHOWSKYAT=0
PANEL=0
NAME=Amateur
EOF
chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
echo "Amateur.mod created with real amateur satellites PLUS 4 injected weather satellites"
echo "Injected weather satellite IDs: 32958 (FENGYUN 3A), 35951 (DMSP F18), 37214 (FENGYUN 3B), 37849 (SUOMI NPP)"

# Record baseline state
grep -i "^SATELLITES=" "${GPREDICT_MOD_DIR}/Amateur.mod" | cut -d= -f2 > /tmp/classify_initial_amateur_satellites
echo "32958;35951;37214;37849" > /tmp/classify_weather_satellite_ids
date +%s > /tmp/task_start_timestamp

# Ensure metric units NOT already set
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^unit=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

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

echo "=== classify_and_reorganize_satellites task setup complete ==="
echo "Starting state:"
echo "  - Amateur.mod: contains 43 satellites including 4 weather sats (32958, 35951, 37214, 37849)"
echo "  - WeatherSats.mod: does not exist (agent must create)"
echo "  - Fairbanks.qth: does not exist (agent must add)"
echo "  - Metric units: not configured"
