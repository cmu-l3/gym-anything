#!/bin/bash
echo "=== Setting up size_pv_to_energy_target task ==="

# Record task start time for anti-gaming
date +%s > /home/ga/.task_start_time

# Clean up any previous task artifacts
rm -f /home/ga/Documents/SAM_Projects/tucson_sizing_result.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/*.py 2>/dev/null || true

# Ensure output directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Ensure PySAM is available (silent install if missing)
python3 -c "import PySAM.Pvwattsv8" 2>/dev/null || {
    echo "PySAM not found, installing..."
    pip3 install NREL-PySAM --break-system-packages 2>/dev/null || pip3 install NREL-PySAM || true
}

# Provide weather data guidance
SOLAR_RES_DIR=""
if [ -f "/home/ga/.SAM/solar_resource_dir.txt" ]; then
    SOLAR_RES_DIR=$(cat /home/ga/.SAM/solar_resource_dir.txt)
fi

# Ensure terminal is available for the agent
if ! pgrep -f "gnome-terminal" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 3
fi

# Focus the terminal
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="