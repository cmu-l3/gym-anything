#!/bin/bash
echo "=== Setting up model_geothermal_binary_plant task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/SAM_Projects
rm -f /home/ga/Documents/SAM_Projects/geothermal_results.json
rm -f /home/ga/Documents/SAM_Projects/geothermal_model.py
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Verify PySAM availability
python3 -c "import PySAM.Geothermal; print('PySAM Geothermal module: OK')" 2>/dev/null || \
    echo "WARNING: PySAM Geothermal module not available"

python3 -c "import PySAM.Lcoefcr; print('PySAM Lcoefcr module: OK')" 2>/dev/null || \
    echo "WARNING: PySAM Lcoefcr module not available"

# Record available weather files for verification
SOLAR_RES=""
if [ -f "/home/ga/.SAM/solar_resource_dir.txt" ]; then
    SOLAR_RES=$(cat /home/ga/.SAM/solar_resource_dir.txt)
fi
if [ -z "$SOLAR_RES" ] || [ ! -d "$SOLAR_RES" ]; then
    SOLAR_RES=$(find /opt/SAM -type d -name "solar_resource" 2>/dev/null | head -1)
fi
if [ -n "$SOLAR_RES" ]; then
    echo "Weather data directory: $SOLAR_RES"
    ls "$SOLAR_RES"/*.csv 2>/dev/null | head -5
    echo "$SOLAR_RES" > /home/ga/.SAM/solar_resource_dir.txt
fi

# Ensure SAM GUI is running (for context)
if ! pgrep -f "sam" > /dev/null 2>&1; then
    SAM_DIR=""
    if [ -f "/opt/SAM/sam_dir.txt" ]; then
        SAM_DIR=$(cat /opt/SAM/sam_dir.txt)
    fi
    if [ -n "$SAM_DIR" ] && [ -x "/usr/local/bin/sam" ]; then
        su - ga -c "DISPLAY=:1 LD_LIBRARY_PATH='${SAM_DIR}/linux_64:${SAM_DIR}' /usr/local/bin/sam &" 2>/dev/null
        sleep 5
    fi
fi

# Maximize and focus any SAM window
DISPLAY=:1 wmctrl -r "SAM" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SAM" 2>/dev/null || true

# Ensure terminal is available
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Screenshot initial state
DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Geothermal task setup complete ==="