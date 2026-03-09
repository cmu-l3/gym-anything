#!/bin/bash
# Setup script for emcomm_regional_network task
# Persona: Pennsylvania RACES/EMCOMM coordinator
# Sets up a partially misconfigured GPredict installation:
#   - Pittsburgh.qth with WRONG altitude (450m instead of correct 230m) and wrong WX code
#   - An incomplete RACES.mod with only SO-50 (27607)
#   - No Erie or Harrisburg QTH files

echo "=== Setting up emcomm_regional_network task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure Amateur.mod is present (carry-over from post_start setup)
if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    mkdir -p "${GPREDICT_MOD_DIR}"
    if [ -f /usr/share/gpredict/data/Amateur.mod ]; then
        cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
        chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
    fi
fi

# 1. Install Pittsburgh.qth with WRONG altitude and wrong WX code
# (the correct values are ALT=230 and WX=KPIT — agent must fix both)
cat > "${GPREDICT_CONF_DIR}/Pittsburgh.qth" << 'EOF'
[GROUND STATION]
LOCATION=Pittsburgh, PA
LAT=40.440600
LON=-79.995900
ALT=450
WX=KXXX
GPSD_SERVER=
GPSD_PORT=2947
EOF
chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
echo "Pittsburgh.qth created with INCORRECT altitude=450 and WX=KXXX"

# 2. Remove any existing Erie or Harrisburg QTH files (clean start)
rm -f "${GPREDICT_CONF_DIR}/Erie.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Harrisburg.qth" 2>/dev/null || true

# 3. Create an INCOMPLETE RACES.mod with only SO-50 (27607)
# Agent must add AO-85 (40967) and ISS (25544)
mkdir -p "${GPREDICT_MOD_DIR}"
cat > "${GPREDICT_MOD_DIR}/RACES.mod" << 'EOF'
[MODULE]
SATELLITES=27607;
QTHFILE=Pittsburgh.qth
SHOWEV=1
SHOWMAP=1
SHOWPOLARPLOT=1
SHOWSKYAT=0
PANEL=0
NAME=RACES
EOF
chown ga:ga "${GPREDICT_MOD_DIR}/RACES.mod"
echo "RACES.mod created with only SO-50 (incomplete — missing AO-85 and ISS)"

# 4. Record baseline state for adversarial robustness
echo "27607" > /tmp/emcomm_initial_races_satellites
echo "Pittsburgh.qth:ALT=450:WX=KXXX" > /tmp/emcomm_initial_pittsburgh_state
date +%s > /tmp/task_start_timestamp

# 5. Update gpredict.cfg to use Pittsburgh as default
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# 6. Launch GPredict
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

echo "=== emcomm_regional_network task setup complete ==="
echo "Starting state:"
echo "  - Pittsburgh.qth: ALT=450 (wrong, should be 230), WX=KXXX (wrong, should be KPIT)"
echo "  - RACES.mod: contains only SO-50 (27607) — needs AO-85 (40967) and ISS (25544)"
echo "  - Erie.qth: missing"
echo "  - Harrisburg.qth: missing"
