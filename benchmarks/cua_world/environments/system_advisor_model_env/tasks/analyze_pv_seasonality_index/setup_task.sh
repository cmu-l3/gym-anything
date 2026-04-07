#!/bin/bash
echo "=== Setting up analyze_pv_seasonality_index task ==="

# Record task start time
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists and has correct permissions
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Clean any pre-existing output files from previous runs to prevent gaming
rm -f /home/ga/Documents/SAM_Projects/seasonality_report.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/*.py /home/ga/Documents/SAM_Projects/*.py 2>/dev/null || true

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Maximize terminal window
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="