#!/bin/bash
echo "=== Setting up CSP Power Tower task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/SAM_Projects
rm -f /home/ga/Documents/SAM_Projects/csp_power_tower_results.json 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/csp_power_tower_model.py 2>/dev/null || true
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Locate SAM directory and weather data
SAM_DIR=""
if [ -f "/opt/SAM/sam_dir.txt" ]; then
    SAM_DIR=$(cat /opt/SAM/sam_dir.txt)
fi

SOLAR_RES=""
if [ -n "$SAM_DIR" ]; then
    SOLAR_RES=$(find "$SAM_DIR" -type d -name "solar_resource" 2>/dev/null | head -1)
fi

mkdir -p /home/ga/.SAM
if [ -n "$SOLAR_RES" ]; then
    echo "$SOLAR_RES" > /home/ga/.SAM/solar_resource_dir.txt
    echo "Found solar resource directory: $SOLAR_RES"
else
    # Fallback to broader search
    SOLAR_RES=$(find /opt/SAM -name "*.csv" -path "*/solar_resource/*" -exec dirname {} \; 2>/dev/null | sort -u | head -1)
    if [ -n "$SOLAR_RES" ]; then
        echo "$SOLAR_RES" > /home/ga/.SAM/solar_resource_dir.txt
    else
        echo "/opt/SAM" > /home/ga/.SAM/solar_resource_dir.txt
    fi
fi
chown -R ga:ga /home/ga/.SAM

# Verify PySAM TcsmoltenSalt is available
python3 -c "import PySAM.TcsmoltenSalt" 2>/dev/null || echo "WARNING: PySAM TcsmoltenSalt test failed"

# Launch SAM GUI if not running (standard SAM environment baseline)
if ! pgrep -f "sam" > /dev/null 2>&1; then
    if [ -n "$SAM_DIR" ]; then
        su - ga -c "DISPLAY=:1 LD_LIBRARY_PATH='${SAM_DIR}/linux_64:${SAM_DIR}:\$LD_LIBRARY_PATH' /usr/local/bin/sam > /tmp/sam_gui.log 2>&1 &" 2>/dev/null || true
        sleep 5
    fi
fi

# Maximize SAM window if present
DISPLAY=:1 wmctrl -r "SAM" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Ensure a terminal is available for the agent to write the Python script
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 3
fi

# Take screenshot of initial state
DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true
if [ ! -f /tmp/task_initial_state.png ]; then
    DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true
fi

echo "=== CSP Power Tower task setup complete ==="