#!/bin/bash
echo "=== Setting up analyze_project_debt_sensitivity_lcoe task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist and are clean of previous runs
mkdir -p /home/ga/Documents/SAM_Projects
rm -f /home/ga/Documents/SAM_Projects/debt_sensitivity.py 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/lcoe_sensitivity.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

chown -R ga:ga /home/ga/Documents/SAM_Projects

# Open a terminal for the user if one isn't already open
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Take an initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="