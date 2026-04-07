#!/bin/bash
echo "=== Setting up evaluate_pv_summer_peak_capacity_value task ==="

# Record task start time
date +%s > /home/ga/.task_start_time

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/capacity_value_report.json 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/calc_capacity_value.py 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

echo "=== Task setup complete ==="