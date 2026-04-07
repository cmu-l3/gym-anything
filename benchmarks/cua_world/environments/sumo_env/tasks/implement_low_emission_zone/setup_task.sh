#!/bin/bash
echo "=== Setting up implement_low_emission_zone task ==="

# Source utility functions if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create clean output directory
mkdir -p /home/ga/SUMO_Output
rm -rf /home/ga/SUMO_Output/*
chown -R ga:ga /home/ga/SUMO_Output

# Ensure no residual SUMO processes are running
echo "Killing any existing SUMO processes..."
pkill -f "sumo-gui" 2>/dev/null || true
pkill -f "sumo " 2>/dev/null || true
pkill -f "netedit" 2>/dev/null || true
sleep 1

# Open a terminal for the user to work in
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_pasubio &"
    sleep 3
fi

# Focus and maximize the terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="