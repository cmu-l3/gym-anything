#!/bin/bash
# Setup script for poes_downlink_schedule_setup task (Very Hard)
# Persona: NOAA meteorologist at Wallops Island
#
# Creates a deliberately misconfigured GPredict state:
#   - Wallops_CDA.qth with WRONG latitude (73.94 instead of 37.94),
#     WRONG longitude direction (East instead of West), and WRONG WX code (KWFF)
#   - POES_Tracking.mod with WRONG satellites (ISS, Hubble, GPS BIIR-2)
#   - Imperial units and local time (should be Metric and UTC)
#   - Default QTH set to Pittsburgh (should be Wallops_CDA)
#
# The agent must audit, fix, configure, and then use pass prediction export.

echo "=== Setting up poes_downlink_schedule_setup task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# ---------------------------------------------------------------
# 1. Ground Station: Wallops_CDA with THREE deliberate errors
# ---------------------------------------------------------------
# Error 1: LAT=73.9402 instead of correct 37.9402 (digits 3/7 swapped)
# Error 2: LON=75.4576 (positive = East) instead of -75.4576 (West)
# Error 3: WX=KWFF instead of correct KWAL
cat > "${GPREDICT_CONF_DIR}/Wallops_CDA.qth" << 'EOF'
[QTH]
LOCATION=Wallops Island, VA
LAT=73.9402
LON=75.4576
ALT=15
WX=KWFF
GPSD_SERVER=
GPSD_PORT=2947
EOF
chown ga:ga "${GPREDICT_CONF_DIR}/Wallops_CDA.qth"
echo "Wallops_CDA.qth created with WRONG lat (73.94), WRONG lon direction (East), WRONG WX (KWFF)"

# ---------------------------------------------------------------
# 2. Keep Pittsburgh.qth as baseline (correct, not part of task)
# ---------------------------------------------------------------
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    # Fix section header: GPredict v2.2 reads [QTH] not [GROUND STATION]
    sed -i 's/^\[GROUND STATION\]/[QTH]/' "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# ---------------------------------------------------------------
# 3. Module: POES_Tracking with WRONG satellites
# ---------------------------------------------------------------
# ISS (25544), Hubble (20580), GPS BIIR-2 (28474) — none are POES
mkdir -p "${GPREDICT_MOD_DIR}"
cat > "${GPREDICT_MOD_DIR}/POES_Tracking.mod" << 'EOF'
[GLOBAL]
SATELLITES=25544;20580;28474;
QTHFILE=Pittsburgh.qth
NAME=POES_Tracking
EOF
chown ga:ga "${GPREDICT_MOD_DIR}/POES_Tracking.mod"
echo "POES_Tracking.mod created with WRONG satellites (ISS, Hubble, GPS)"

# Remove Amateur.mod to reduce distraction (only POES_Tracking visible)
rm -f "${GPREDICT_MOD_DIR}/Amateur.mod" 2>/dev/null || true

# ---------------------------------------------------------------
# 4. Preferences: set to WRONG values
# ---------------------------------------------------------------
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    # GPredict uses USE_IMPERIAL and USE_LOCAL_TIME keys under [GLOBAL]
    # (discovered by toggling checkboxes in the GUI and reading the config)

    # Set Imperial units — agent must change to Metric
    sed -i '/^USE_IMPERIAL=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^unit=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^\[GLOBAL\]/a USE_IMPERIAL=true' "${GPREDICT_CONF_DIR}/gpredict.cfg"

    # Set local time — agent must change to UTC
    sed -i '/^USE_LOCAL_TIME=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^TFORMAT=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^\[GLOBAL\]/a USE_LOCAL_TIME=true' "${GPREDICT_CONF_DIR}/gpredict.cfg"

    # Set default QTH to Pittsburgh — agent must change to Wallops_CDA
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    else
        sed -i '/^\[GLOBAL\]/a DEFAULT_QTH=Pittsburgh.qth' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi

    # Set OPEN_MODULES to POES_Tracking so GPredict shows the module on startup
    if grep -q "^OPEN_MODULES=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^OPEN_MODULES=.*/OPEN_MODULES=POES_Tracking/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    else
        sed -i '/^\[GLOBAL\]/a OPEN_MODULES=POES_Tracking' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# ---------------------------------------------------------------
# 5. TLE data: copy cache files and ensure all required satellites
#    have .sat data files so they appear in GPredict's catalog
# ---------------------------------------------------------------
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
if [ -f /workspace/data/weather.txt ]; then
    cp /workspace/data/weather.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
fi
if [ -f /workspace/data/stations.txt ]; then
    cp /workspace/data/stations.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
fi
if [ -f /workspace/data/amateur.txt ]; then
    cp /workspace/data/amateur.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
fi
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true

# Create .sat files for any POES satellites missing from the satdata directory.
# These are extracted from the weather.txt TLE file to ensure all target
# satellites are available in GPredict's catalog without requiring network access.
SATDATA_DIR="${GPREDICT_CONF_DIR}/satdata"
WEATHER_TLE="${GPREDICT_CONF_DIR}/satdata/cache/weather.txt"

if [ -f "$WEATHER_TLE" ]; then
    # Create .sat files for each required POES satellite if missing
    # Format: extract name line, TLE line 1, TLE line 2 from the 3-line TLE format
    python3 << 'PYEOF'
import os, re

satdata_dir = "/home/ga/.config/Gpredict/satdata"
weather_tle = os.path.join(satdata_dir, "cache", "weather.txt")

# Required POES satellite NORAD IDs
required_ids = [25338, 28654, 33591, 38771, 43689, 37849]

# Read and parse the TLE file (3-line format: name, line1, line2)
with open(weather_tle, 'r') as f:
    lines = [l.rstrip() for l in f.readlines() if l.strip()]

i = 0
while i < len(lines) - 2:
    if lines[i+1].startswith('1 ') and lines[i+2].startswith('2 '):
        name = lines[i].strip()
        tle1 = lines[i+1].strip()
        tle2 = lines[i+2].strip()
        # Extract NORAD ID from TLE line 1
        parts = tle1.split()
        if len(parts) >= 2:
            try:
                norad_id = int(parts[1].rstrip('U'))
            except ValueError:
                i += 3
                continue
            sat_file = os.path.join(satdata_dir, f"{norad_id}.sat")
            if norad_id in required_ids and not os.path.exists(sat_file):
                with open(sat_file, 'w') as sf:
                    sf.write(f"[Satellite]\nVERSION=1.1\nNAME={name}\nNICKNAME={name}\nTLE1={tle1}\nTLE2={tle2}\n")
                os.chown(sat_file, 1000, 1000)  # ga user
                print(f"Created {sat_file} for {name} (NORAD {norad_id})")
        i += 3
    else:
        i += 1
PYEOF
fi

# ---------------------------------------------------------------
# 6. Ensure ~/Documents exists, remove stale pass export files
# ---------------------------------------------------------------
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
rm -f /home/ga/Documents/METOP_C_passes.txt 2>/dev/null || true
rm -f /home/ga/Documents/METOP-C*.txt 2>/dev/null || true
rm -f /home/ga/Documents/metop*.txt 2>/dev/null || true

# ---------------------------------------------------------------
# 7. Record task start timestamp (AFTER all cleanup)
# ---------------------------------------------------------------
date +%s > /tmp/task_start_timestamp

# ---------------------------------------------------------------
# 8. Launch GPredict
# ---------------------------------------------------------------
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
    # Dismiss any startup dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== poes_downlink_schedule_setup task setup complete ==="
echo "Starting state:"
echo "  - Wallops_CDA.qth: LAT=73.94 (wrong), LON=75.46 East (wrong dir), WX=KWFF (wrong)"
echo "  - POES_Tracking.mod: contains ISS/Hubble/GPS (all wrong for POES)"
echo "  - Preferences: Imperial units, local time, default=Pittsburgh"
echo "  - Pass export file: does not exist"
