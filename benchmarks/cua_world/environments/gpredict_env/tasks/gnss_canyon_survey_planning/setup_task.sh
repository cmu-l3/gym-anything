#!/bin/bash
# Setup script for gnss_canyon_survey_planning task
# Persona: Precision drone surveyor in a deep canyon
# Sets up the default Amateur radio state and injects GNSS TLE data.

echo "=== Setting up gnss_canyon_survey_planning task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure Amateur.mod is present (default state to be deleted)
mkdir -p "${GPREDICT_MOD_DIR}"
if [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Ensure default gpredict.cfg is present with default MIN_EL (0)
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^MIN_EL=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
fi

# Remove Zion_Canyon.qth if it exists
rm -f "${GPREDICT_CONF_DIR}/Zion_Canyon.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/zion_canyon.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Zion.qth" 2>/dev/null || true

# Remove GNSS_Survey.mod if it exists
rm -f "${GPREDICT_MOD_DIR}/GNSS_Survey.mod" 2>/dev/null || true

# Inject GNSS satellites into the cache so the agent can find them
# We append to amateur.txt as it is natively loaded and indexed by GPredict
CACHE_FILE="${GPREDICT_CONF_DIR}/satdata/cache/amateur.txt"
mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"

if [ -f /workspace/data/amateur.txt ]; then
    cp /workspace/data/amateur.txt "$CACHE_FILE"
else
    touch "$CACHE_FILE"
fi

# Add the specific NAVSTAR and GALILEO satellites
cat >> "$CACHE_FILE" << 'EOF'
NAVSTAR 73 (USA 289)
1 43873U 18109A   23315.42080344 -.00000030  00000-0  00000+0 0  9990
2 43873  55.3040 286.0820 0002164 121.5794 238.4111  2.00566373 36585
NAVSTAR 74 (USA 293)
1 44431U 19044A   23316.32742964 -.00000045  00000-0  00000+0 0  9991
2 44431  55.2982  56.0950 0004071 270.2117  89.7719  2.00562916 30784
NAVSTAR 75 (USA 304)
1 45854U 20043A   23316.03554162 -.00000034  00000-0  00000+0 0  9995
2 45854  55.3023  66.5208 0003104   7.8093 352.1939  2.00569106 24204
GSAT0223 (GALILEO 25)
1 49589U 21119A   23316.27508688 -.00000045  00000-0  00000+0 0  9997
2 49589  56.2413 135.5323 0003264   8.7237 351.2828  1.70475306 14207
GSAT0224 (GALILEO 26)
1 49590U 21119B   23315.68962057 -.00000044  00000-0  00000+0 0  9991
2 49590  56.2407 135.5342 0002871   9.7997 350.2066  1.70475154 14197
EOF
chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache"

# Record timestamp for anti-gaming verification
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
else
    # Maximize and focus
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Task setup complete ==="