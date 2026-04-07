#!/bin/bash
echo "=== Setting up model_generic_small_hydro task ==="

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/small_hydro_model.py 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/small_hydro_results.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record task start time
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Take an initial screenshot to prove starting state
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="