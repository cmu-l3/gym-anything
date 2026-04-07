#!/bin/bash
# Setup script for hab_telemetry_relay_setup task
# Persona: University HAB Team Coordinator
# Sets up GPredict with:
#   - An obsolete L_Band_Test.mod that must be deleted
#   - No Launch or Recovery QTH files
#   - Metric units enforced (so agent must change to Imperial)

echo "=== Setting up hab_telemetry_relay_setup task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Ensure baseline configurations are in place
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
    chown ga:ga "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

if [ ! -f "${GPREDICT_MOD_DIR}/Amateur.mod" ] && [ -f /usr/share/gpredict/data/Amateur.mod ]; then
    mkdir -p "${GPREDICT_MOD_DIR}"
    cp /usr/share/gpredict/data/Amateur.mod "${GPREDICT_MOD_DIR}/Amateur.mod"
    chown ga:ga "${GPREDICT_MOD_DIR}/Amateur.mod"
fi

# 1. Clean up any existing targets (ensure clean slate)
rm -f "${GPREDICT_CONF_DIR}/Launch_Site.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/LaunchSite.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/Recovery_Team.qth" 2>/dev/null || true
rm -f "${GPREDICT_CONF_DIR}/RecoveryTeam.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/HAB_Relays.mod" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/HABRelays.mod" 2>/dev/null || true

# 2. Create the OBSOLETE module that must be deleted
mkdir -p "${GPREDICT_MOD_DIR}"
cat > "${GPREDICT_MOD_DIR}/L_Band_Test.mod" << 'EOF'
[MODULE]
SATELLITES=25338;
QTHFILE=Pittsburgh.qth
SHOWEV=1
SHOWMAP=1
SHOWPOLARPLOT=1
SHOWSKYAT=0
PANEL=0
NAME=L_Band_Test
EOF
chown ga:ga "${GPREDICT_MOD_DIR}/L_Band_Test.mod"
echo "Created obsolete L_Band_Test.mod"

# 3. Enforce METRIC units in gpredict.cfg (unit=0) so agent must change to IMPERIAL (unit=1)
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^unit=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    sed -i '/^\[misc\]/a unit=0' "${GPREDICT_CONF_DIR}/gpredict.cfg"
else
    mkdir -p "${GPREDICT_CONF_DIR}"
    cat > "${GPREDICT_CONF_DIR}/gpredict.cfg" << 'EOF'
[misc]
unit=0
[GLOBAL]
DEFAULT_QTH=Pittsburgh.qth
EOF
fi
chown ga:ga "${GPREDICT_CONF_DIR}/gpredict.cfg"

# 4. Load real satellite data (amateur sats) into cache
if [ -f /workspace/data/amateur.txt ]; then
    mkdir -p "${GPREDICT_CONF_DIR}/satdata/cache"
    cp /workspace/data/amateur.txt "${GPREDICT_CONF_DIR}/satdata/cache/"
    cp /workspace/data/stations.txt "${GPREDICT_CONF_DIR}/satdata/cache/" 2>/dev/null || true
    chown -R ga:ga "${GPREDICT_CONF_DIR}/satdata/cache/"
fi

# 5. Launch GPredict and focus window
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

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== hab_telemetry_relay_setup setup complete ==="