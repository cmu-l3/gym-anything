#!/bin/bash
echo "=== Setting up compare_itc_vs_ptc_incentives task ==="

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/itc_vs_ptc_comparison.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Clear any cached Python scripts from previous runs to prevent gaming
rm -f /home/ga/*.py /home/ga/pv_*.py /home/ga/sam_*.py 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/*.py 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Launch a terminal for the agent if one isn't already open
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Take an initial state screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="