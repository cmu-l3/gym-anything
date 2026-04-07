#!/bin/bash
echo "=== Setting up evaluate_pv_lcoe_risk_monte_carlo task ==="

# Clean any pre-existing output files from previous runs to ensure clean state
rm -f /home/ga/Documents/SAM_Projects/monte_carlo_results.json 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/monte_carlo_lcoe.py 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

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

# Take initial state screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="