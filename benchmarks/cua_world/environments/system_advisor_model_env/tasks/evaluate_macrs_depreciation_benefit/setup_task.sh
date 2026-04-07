#!/bin/bash
echo "=== Setting up evaluate_macrs_depreciation_benefit task ==="

# Clean any pre-existing output files
rm -f /home/ga/Documents/SAM_Projects/depreciation_results.json 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/depreciation_model.py 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record task start time
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Open terminal
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

echo "=== Task setup complete ==="