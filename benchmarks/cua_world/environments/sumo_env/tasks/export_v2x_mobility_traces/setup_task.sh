#!/bin/bash
echo "=== Setting up export_v2x_mobility_traces task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Clean up any existing output files
rm -rf /home/ga/SUMO_Output/*
mkdir -p /home/ga/SUMO_Output
chown ga:ga /home/ga/SUMO_Output

# Ensure terminal is open since this is a CLI-heavy task
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
fi

# Maximize terminal for agent visibility
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="