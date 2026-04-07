#!/bin/bash
echo "=== Setting up evaluate_ev_fleet_pv_offset task ==="

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/ev_fleet_pv_analysis.json 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/ev_fleet_analysis.py 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Clear any cached Python scripts from previous task runs
rm -f /home/ga/*.py 2>/dev/null || true

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Take an initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="