#!/bin/bash
echo "=== Setting up lifetime degradation task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents

# Remove any previous results (clean state)
rm -f /home/ga/Documents/SAM_Projects/lifetime_degradation_results.json

# Verify PySAM is available
python3 -c "import PySAM.Pvwattsv8; print('PySAM Pvwattsv8 OK')" 2>/dev/null || {
    echo "ERROR: PySAM.Pvwattsv8 not available, attempting install..."
    pip3 install NREL-PySAM --break-system-packages 2>/dev/null || pip3 install NREL-PySAM
}

# Locate and record solar resource directory
SAM_DIR=""
if [ -f "/opt/SAM/sam_dir.txt" ]; then
    SAM_DIR=$(cat /opt/SAM/sam_dir.txt)
fi

SOLAR_RES=""
if [ -n "$SAM_DIR" ]; then
    SOLAR_RES=$(find "$SAM_DIR" -type d -name "solar_resource" 2>/dev/null | head -1)
fi

if [ -n "$SOLAR_RES" ]; then
    echo "$SOLAR_RES" > /home/ga/.SAM/solar_resource_dir.txt
    echo "Solar resource directory: $SOLAR_RES"
else
    echo "WARNING: solar_resource directory not found in SAM installation"
    # Try broader search
    SOLAR_RES=$(find /opt/SAM -type d -name "solar_resource" 2>/dev/null | head -1)
    if [ -n "$SOLAR_RES" ]; then
        echo "$SOLAR_RES" > /home/ga/.SAM/solar_resource_dir.txt
    fi
fi

# Ensure SAM GUI is visible (for initial screenshot context)
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sam\|system advisor"; then
    if [ -x /usr/local/bin/sam ] && [ -n "$SAM_DIR" ]; then
        su - ga -c "DISPLAY=:1 LD_LIBRARY_PATH='${SAM_DIR}/linux_64:${SAM_DIR}' /usr/local/bin/sam > /tmp/sam_gui.log 2>&1 &"
        sleep 5
    fi
fi

# Ensure a terminal is open and focused
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 3
fi

# Maximize SAM GUI if open
DISPLAY=:1 wmctrl -r "System Advisor Model" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Focus terminal
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial state screenshot
DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Lifetime degradation task setup complete ==="