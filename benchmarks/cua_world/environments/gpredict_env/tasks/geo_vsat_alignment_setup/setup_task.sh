#!/bin/bash
# Setup script for geo_vsat_alignment_setup task

echo "=== Setting up geo_vsat_alignment_setup task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"
GPREDICT_TRSP_DIR="${GPREDICT_CONF_DIR}/trsp"

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Create necessary directories
mkdir -p "${GPREDICT_MOD_DIR}"
mkdir -p "${GPREDICT_TRSP_DIR}"
mkdir -p "${GPREDICT_CONF_DIR}/satdata"

# Ensure Pittsburgh.qth is installed as default
if [ -f /workspace/config/Pittsburgh.qth ]; then
    cp /workspace/config/Pittsburgh.qth "${GPREDICT_CONF_DIR}/Pittsburgh.qth"
fi

# Clean up task-specific files if they exist to ensure clean slate
rm -f "${GPREDICT_CONF_DIR}/Omaha_DataCenter.qth" 2>/dev/null || true
rm -f "${GPREDICT_MOD_DIR}/GEO_Alignment.mod" 2>/dev/null || true
rm -f "${GPREDICT_TRSP_DIR}/43013.trsp" 2>/dev/null || true
rm -f "${GPREDICT_TRSP_DIR}/51850.trsp" 2>/dev/null || true
rm -f "${GPREDICT_TRSP_DIR}/36516.trsp" 2>/dev/null || true

# Inject the GEO satellites directly into the database so the agent can find them
# This bypasses the need for the agent to figure out internet TLE updates
cat > "${GPREDICT_CONF_DIR}/satdata/43013.sat" << 'EOF'
[Satellite]
VERSION=1.1
NAME=GOES 16
NICKNAME=GOES 16
TLE1=1 43013U 16071A   25045.50000000  .00000000  00000-0  00000-0 0  9990
TLE2=2 43013   0.0100 000.0000 0000000 000.0000 000.0000  1.00270000    00
EOF

cat > "${GPREDICT_CONF_DIR}/satdata/51850.sat" << 'EOF'
[Satellite]
VERSION=1.1
NAME=GOES 18
NICKNAME=GOES 18
TLE1=1 51850U 22021A   25045.50000000  .00000000  00000-0  00000-0 0  9990
TLE2=2 51850   0.0100 000.0000 0000000 000.0000 000.0000  1.00270000    00
EOF

cat > "${GPREDICT_CONF_DIR}/satdata/36516.sat" << 'EOF'
[Satellite]
VERSION=1.1
NAME=SES-1
NICKNAME=SES-1
TLE1=1 36516U 10016A   25045.50000000  .00000000  00000-0  00000-0 0  9990
TLE2=2 36516   0.0100 000.0000 0000000 000.0000 000.0000  1.00270000    00
EOF

# Ensure gpredict.cfg does NOT have UTC time enabled (default to local)
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    sed -i '/^utc=/d' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    if grep -q "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg"; then
        sed -i 's/^DEFAULT_QTH=.*/DEFAULT_QTH=Pittsburgh.qth/' "${GPREDICT_CONF_DIR}/gpredict.cfg"
    fi
fi

# Fix permissions
chown -R ga:ga "${GPREDICT_CONF_DIR}"

# Record start time for verification
date +%s > /tmp/task_start_time.txt

# Launch GPredict
echo "Launching GPredict..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid gpredict > /tmp/gpredict_task.log 2>&1 &"
sleep 5

# Wait for GPredict window
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Gpredict"; then
        echo "GPredict window detected"
        break
    fi
    sleep 2
done

# Focus and maximize window
DISPLAY=:1 wmctrl -r "Gpredict" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Gpredict" 2>/dev/null || true
sleep 1

# Dismiss potential startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial_screenshot.png 2>/dev/null || true

echo "=== geo_vsat_alignment_setup task setup complete ==="