#!/bin/bash
echo "=== Setting up compute_utility_pv_lcoe task ==="

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/utility_pv_lcoe_result.json 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/compute_lcoe.py 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record task start time (for anti-gaming checks)
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Ensure SAM window is visible and maximized (even though this task is mostly scripting, it fits the environment expectations)
DISPLAY=:1 wmctrl -r "SAM" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="