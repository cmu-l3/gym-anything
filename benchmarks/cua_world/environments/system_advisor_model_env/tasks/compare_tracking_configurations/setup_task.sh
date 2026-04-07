#!/bin/bash
echo "=== Setting up compare_tracking_configurations task ==="

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/tracking_comparison.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Clear any cached Python scripts
rm -f /home/ga/*.py 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/*.py 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Take initial state screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="