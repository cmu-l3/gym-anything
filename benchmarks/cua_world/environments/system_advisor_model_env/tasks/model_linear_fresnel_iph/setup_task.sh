#!/bin/bash
echo "=== Setting up model_linear_fresnel_iph task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Clean up any files from previous runs
rm -f /home/ga/Documents/SAM_Projects/linear_fresnel_iph.py 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/linear_fresnel_iph_results.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Ensure target directory exists and has correct permissions
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Ensure terminal is available and focused for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 3
fi

DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot showing environment ready
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="