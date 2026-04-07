#!/bin/bash
# Setup script for config_audit_cleanup task
# Persona: New Satellite Operations Engineer
# Sets up a messy, misconfigured GPredict state that requires correction and deletion.

echo "=== Setting up config_audit_cleanup task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

mkdir -p "${GPREDICT_CONF_DIR}"
mkdir -p "${GPREDICT_MOD_DIR}"

# Ensure standard Pittsburgh QTH exists as a baseline
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# 1. Create Bogus_Test.qth (to be deleted)
cat > "${GPREDICT_CONF_DIR}/Bogus_Test.qth" << 'EOF'
[GROUND STATION]
NAME=Bogus_Test
LOCATION=Null Island
DESCRIPTION=Test station - should not exist
LAT=0.000000
LON=0.000000
ALT=0
QRA=JJ00aa
WX=
EOF
echo "Bogus_Test.qth created."

# 2. Create Houston.qth with WRONG altitude (999m instead of 14m)
cat > "${GPREDICT_CONF_DIR}/Houston.qth" << 'EOF'
[GROUND STATION]
NAME=Houston
LOCATION=Houston, TX
DESCRIPTION=Johnson Space Center
LAT=29.550200
LON=-95.097000
ALT=999
QRA=EL29en
WX=KHOU
EOF
echo "Houston.qth created with incorrect altitude (999m)."

# 3. Create contaminated Research.mod (ISS + weather sats)
# Agent must keep 25544, 36086, 49044 and remove 37849, 32958
cat > "${GPREDICT_MOD_DIR}/Research.mod" << 'EOF'
[MODULE]
SATELLITES=25544;36086;49044;37849;32958;
QTHFILE=Pittsburgh.qth
SHOWEV=1
SHOWMAP=1
SHOWPOLARPLOT=1
SHOWSKYAT=0
PANEL=0
NAME=Research
EOF
echo "Research.mod created with mixed satellites."

# 4. Create Old_Demo.mod (to be deleted)
cat > "${GPREDICT_MOD_DIR}/Old_Demo.mod" << 'EOF'
[MODULE]
SATELLITES=25544;
QTHFILE=Pittsburgh.qth
SHOWEV=1
SHOWMAP=1
SHOWPOLARPLOT=1
SHOWSKYAT=0
PANEL=0
NAME=Old_Demo
EOF
echo "Old_Demo.mod created."

# 5. Ensure Amateur.mod exists (to remain untouched)
if [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# Make sure Svalbard.qth does NOT exist yet
rm -f "${GPREDICT_CONF_DIR}/Svalbard.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/svalbard.qth" 2>/dev/null || true

# Set appropriate permissions
chown -R ga:ga "${GPREDICT_CONF_DIR}"

# Load TLE data into cache so names are displayed
if [ -d /workspace/data ]; then
    mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
    cp /workspace/data/stations.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
    cp /workspace/data/weather.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
    cp /workspace/data/amateur.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
    chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache"
fi

# Ensure default QTH is Pittsburgh.qth initially
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    else
        sed -i '/^\[GLOBAL\]/a DEFAULT_QTH=Pittsburgh.qth' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Record start time for verification
date +%s > /tmp/task_start_time.txt

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
    # Dismiss any startup tips
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="