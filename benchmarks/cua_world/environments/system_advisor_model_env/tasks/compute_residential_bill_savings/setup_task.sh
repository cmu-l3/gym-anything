#!/bin/bash
echo "=== Setting up compute_residential_bill_savings task ==="

# Clean pre-existing task artifacts to prevent gaming
rm -f /home/ga/Documents/SAM_Projects/phoenix_bill_savings.json 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/bill_savings_analysis.py 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Clear cached Python files in home
rm -f /home/ga/*.py /home/ga/pv_*.py /home/ga/sam_*.py 2>/dev/null || true

# Record task start time
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Launch terminal if not running
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="