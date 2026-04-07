#!/bin/bash
echo "=== Setting up query_cec_module_database task ==="

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

# Ensure clean state - remove any previous task artifacts
mkdir -p /home/ga/Documents/SAM_Projects
rm -f /home/ga/Documents/SAM_Projects/premium_modules_report.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/ground_truth_cec.csv 2>/dev/null || true

# Ensure proper permissions
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Open a terminal for the agent to use
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    echo "Starting terminal for agent..."
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 3
fi

# Ensure terminal is focused
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take an initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="