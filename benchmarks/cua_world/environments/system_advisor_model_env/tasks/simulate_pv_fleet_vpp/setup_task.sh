#!/bin/bash
echo "=== Setting up simulate_pv_fleet_vpp task ==="

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Clean any pre-existing output files from previous runs to prevent false positives
rm -f /home/ga/Documents/SAM_Projects/vpp_fleet_results.json 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/vpp_simulation.py 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Clear bash history to accurately track agent's commands
> /home/ga/.bash_history

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 3
fi

# Maximize the terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot showing clean environment
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="