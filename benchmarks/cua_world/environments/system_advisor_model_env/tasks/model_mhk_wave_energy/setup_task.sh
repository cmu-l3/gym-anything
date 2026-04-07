#!/bin/bash
echo "=== Setting up MHK Wave Energy task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Remove any pre-existing result file (clean state)
rm -f /home/ga/Documents/SAM_Projects/wave_energy_results.json

# Test PySAM installation (silent to agent)
su - ga -c "python3 -c 'import PySAM.MhkWave'" 2>/dev/null || true

# Ensure terminal is open for agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 3
fi

# Maximize terminal window
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

echo "=== MHK Wave Energy task setup complete ==="