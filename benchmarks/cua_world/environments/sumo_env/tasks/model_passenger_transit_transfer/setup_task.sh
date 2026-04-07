#!/bin/bash
echo "=== Setting up model_passenger_transit_transfer task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Clean output directory to ensure a pristine starting state
rm -rf /home/ga/SUMO_Output/*
mkdir -p /home/ga/SUMO_Output
chown -R ga:ga /home/ga/SUMO_Output

# Make sure SUMO isn't already running from a previous task
kill_sumo
sleep 1

# Launch a terminal for the user, set to the scenario directory
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_pasubio &"
    sleep 3
fi

# Maximize the terminal for visibility
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Capture the initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="